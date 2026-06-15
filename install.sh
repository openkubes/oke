#!/bin/sh
# =============================================================================
# OKE Install Script
# Usage:
#   curl -sfL https://get.openkubes.ai | sh -s - server
#   curl -sfL https://get.openkubes.ai | sh -s - agent
#   curl -sfL https://get.openkubes.ai | OKE_NATIVE=auto sh -s - server
#
# Environment variables:
#   OKE_VERSION    - OKE version to install (default: latest)
#   OKE_NATIVE     - Set to 'auto' to enable ok-linux native features
#   OKE_URL        - OKE server URL (for agent mode)
#   OKE_TOKEN      - OKE cluster token (for agent mode)
#   INSTALL_OKE_BIN_DIR    - Binary install dir (default: /usr/local/bin)
#   INSTALL_OKE_SYSTEMD_DIR - Systemd unit dir (default: /etc/systemd/system)
# =============================================================================
set -e

# -----------------------------------------------------------------------------
# Defaults
# -----------------------------------------------------------------------------
GITHUB_URL="https://github.com/openkubes/oke/releases"
INSTALL_OKE_BIN_DIR="${INSTALL_OKE_BIN_DIR:-/usr/local/bin}"
INSTALL_OKE_SYSTEMD_DIR="${INSTALL_OKE_SYSTEMD_DIR:-/etc/systemd/system}"
OKE_DATA_DIR="/var/lib/openkubes/oke"
OKE_CONFIG_DIR="/etc/openkubes/oke"

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------
info() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*" >&2; }
fatal() { echo "[ERROR] $*" >&2; exit 1; }

# Detect architecture
detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64)  echo "amd64" ;;
        aarch64|arm64) echo "arm64" ;;
        *) fatal "Unsupported architecture: $(uname -m)" ;;
    esac
}

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        echo "$ID"
    elif [ -f /etc/redhat-release ]; then
        echo "rhel"
    else
        echo "linux"
    fi
}

# Detect if running on ok-linux
detect_ok_linux() {
    if [ -f /etc/ok-linux-release ] || \
       ([ -f /etc/os-release ] && grep -q "ok-linux" /etc/os-release 2>/dev/null); then
        return 0
    fi
    return 1
}

# Get latest OKE version from GitHub API
get_latest_version() {
    if command -v curl > /dev/null 2>&1; then
        curl -sfL "https://api.github.com/repos/openkubes/oke/releases/latest" | grep '"tag_name"' | cut -d'"' -f4
    elif command -v wget > /dev/null 2>&1; then
        wget -qO- "https://api.github.com/repos/openkubes/oke/releases/latest" | grep '"tag_name"' | cut -d'"' -f4
    else
        fatal "curl or wget required"
    fi
}

# Download file
download() {
    url="$1"
    dest="$2"
    info "Downloading $url"
    if command -v curl > /dev/null 2>&1; then
        curl -sfL "$url" -o "$dest"
    elif command -v wget > /dev/null 2>&1; then
        wget -qO "$dest" "$url"
    else
        fatal "curl or wget required"
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------
main() {
    ROLE="${1:-server}"

    # Validate role
    case "$ROLE" in
        server|agent) ;;
        *) fatal "Unknown role '$ROLE'. Use 'server' or 'agent'." ;;
    esac

    # Root check
    if [ "$(id -u)" -ne 0 ]; then
        fatal "This script must be run as root. Try: sudo sh -"
    fi

    ARCH=$(detect_arch)
    OS=$(detect_os)

    info "OKE Install Script"
    info "  Role:   $ROLE"
    info "  Arch:   $ARCH"
    info "  OS:     $OS"

    # Detect ok-linux
    IS_OK_LINUX=false
    if detect_ok_linux || [ "${OKE_NATIVE:-}" = "auto" ]; then
        if detect_ok_linux; then
            IS_OK_LINUX=true
            info "  Platform: ok-linux detected — native features will be enabled"
        elif [ "${OKE_NATIVE:-}" = "auto" ]; then
            info "  Platform: OKE_NATIVE=auto set, but ok-linux not detected — standard install"
        fi
    fi

    # Resolve version
    if [ -z "${OKE_VERSION:-}" ]; then
        info "Resolving latest OKE version..."
        OKE_VERSION=$(get_latest_version)
        [ -n "$OKE_VERSION" ] || fatal "Could not determine latest OKE version"
    fi
    info "  Version: $OKE_VERSION"

    # Download binary
    BINARY_URL="${GITHUB_URL}/download/${OKE_VERSION}/oke-linux-${ARCH}"
    TMP_BIN=$(mktemp)
    download "$BINARY_URL" "$TMP_BIN"

    # Verify checksum if sha256sums available
    CHECKSUM_URL="${GITHUB_URL}/download/${OKE_VERSION}/sha256sums.txt"
    TMP_SUMS=$(mktemp)
    if download "$CHECKSUM_URL" "$TMP_SUMS" 2>/dev/null; then
        info "Verifying checksum..."
        EXPECTED=$(grep "oke-linux-${ARCH}" "$TMP_SUMS" | awk '{print $1}')
        ACTUAL=$(sha256sum "$TMP_BIN" | awk '{print $1}')
        if [ "$EXPECTED" != "$ACTUAL" ]; then
            rm -f "$TMP_BIN" "$TMP_SUMS"
            fatal "Checksum mismatch! Expected: $EXPECTED  Got: $ACTUAL"
        fi
        info "  Checksum OK"
    fi
    rm -f "$TMP_SUMS"

    # Install binary
    info "Installing OKE binary to ${INSTALL_OKE_BIN_DIR}/oke ..."
    install -m 755 "$TMP_BIN" "${INSTALL_OKE_BIN_DIR}/oke"
    rm -f "$TMP_BIN"

    # Create directories
    mkdir -p "$OKE_DATA_DIR" "$OKE_CONFIG_DIR"

    # Write config
    CONFIG_FILE="${OKE_CONFIG_DIR}/config.yaml"
    if [ ! -f "$CONFIG_FILE" ]; then
        info "Writing default config to $CONFIG_FILE ..."
        cat > "$CONFIG_FILE" << EOF
# OKE Configuration
# https://github.com/openkubes/oke
runtime-image: rancher/rke2-runtime:v1.35.5-rke2r2
data-dir: /var/lib/rancher/rke2
EOF
        if [ "$ROLE" = "agent" ]; then
            [ -n "${OKE_URL:-}" ] && echo "server: ${OKE_URL}" >> "$CONFIG_FILE"
            [ -n "${OKE_TOKEN:-}" ] && echo "token: ${OKE_TOKEN}" >> "$CONFIG_FILE"
        fi
        if [ "$IS_OK_LINUX" = "true" ]; then
            cat >> "$CONFIG_FILE" << EOF

# ok-linux native features
kubevirt: true
ebpf-acceleration: true
EOF
        fi
    fi

    # Write systemd unit
    UNIT_NAME="oke-${ROLE}"
    UNIT_FILE="${INSTALL_OKE_SYSTEMD_DIR}/${UNIT_NAME}.service"
    info "Writing systemd unit ${UNIT_FILE} ..."
    cat > "$UNIT_FILE" << EOF
[Unit]
Description=OKE — OpenKubes Kubernetes Engine (${ROLE})
Documentation=https://github.com/openkubes/oke
Wants=network-online.target
After=network-online.target

[Service]
Type=notify
EnvironmentFile=-/etc/default/%N
EnvironmentFile=-/etc/sysconfig/%N
EnvironmentFile=-${OKE_CONFIG_DIR}/oke-env
KillMode=process
Delegate=yes
LimitNOFILE=1048576
LimitNPROC=infinity
LimitCORE=infinity
TasksMax=infinity
TimeoutStartSec=0
Restart=always
RestartSec=5s
ExecStartPre=-/sbin/modprobe br_netfilter
ExecStartPre=-/sbin/modprobe overlay
ExecStart=${INSTALL_OKE_BIN_DIR}/oke ${ROLE} \
    --config ${OKE_CONFIG_DIR}/config.yaml

[Install]
WantedBy=multi-user.target
EOF

    # Fix systemd service type for stability
    sed -i 's/Type=notify/Type=simple/' "${INSTALL_OKE_SYSTEMD_DIR}/${UNIT_NAME}.service" 2>/dev/null || true

    # Enable & start
    info "Enabling and starting ${UNIT_NAME}.service ..."
    systemctl daemon-reload
    systemctl enable "${UNIT_NAME}.service"
    systemctl start "${UNIT_NAME}.service"

    # Wait for OKE to generate its runtime files
    info "Waiting for OKE to initialize (30s)..."
    sleep 30

    # Patch image tags — binary currently embeds :latest for some images
    # This will be fixed in a future OKE release
    if [ "$ROLE" = "server" ]; then
        info "Patching image tags..."

        IMAGES_DIR="${DATA_DIR:-/var/lib/rancher/rke2}/agent/images"
        MANIFESTS_DIR="${DATA_DIR:-/var/lib/rancher/rke2}/agent/pod-manifests"
        CONTAINERD_CONFIG="${DATA_DIR:-/var/lib/rancher/rke2}/agent/etc/containerd/config.toml"

        K8S_TAG="v1.35.5-rke2r2-build20260521"
        ETCD_TAG="v3.6.7-k3s1-build20260512"
        PAUSE_TAG="3.6"
        CCM_TAG="v1.35.4-0.20260415195656-e51c0636351d-build20260415"
        RUNTIME_TAG="v1.35.5-rke2r2"

        # Patch image.txt files
        for f in \
            "${IMAGES_DIR}/kube-apiserver-image.txt" \
            "${IMAGES_DIR}/kube-controller-manager-image.txt" \
            "${IMAGES_DIR}/kube-scheduler-image.txt" \
            "${IMAGES_DIR}/kube-proxy-image.txt"; do
            [ -f "$f" ] && sed -i "s|rancher/hardened-kubernetes:latest|rancher/hardened-kubernetes:${K8S_TAG}|g" "$f"
        done

        [ -f "${IMAGES_DIR}/etcd-image.txt" ] && \
            sed -i "s|rancher/hardened-etcd:latest|rancher/hardened-etcd:${ETCD_TAG}|g" \
            "${IMAGES_DIR}/etcd-image.txt"

        [ -f "${IMAGES_DIR}/cloud-controller-manager-image.txt" ] && \
            sed -i "s|rancher/rke2-cloud-provider:latest|rancher/rke2-cloud-provider:${CCM_TAG}|g" \
            "${IMAGES_DIR}/cloud-controller-manager-image.txt"

        [ -f "${IMAGES_DIR}/runtime-image.txt" ] && \
            sed -i "s|rancher/rke2-runtime:latest|rancher/rke2-runtime:${RUNTIME_TAG}|g" \
            "${IMAGES_DIR}/runtime-image.txt"

        # Patch containerd config (pause image) — wait for file to be generated
        info "Waiting for containerd config to be generated..."
        CONTAINERD_WAIT=0
        while [ $CONTAINERD_WAIT -lt 60 ]; do
            if [ -f "${CONTAINERD_CONFIG}" ]; then
                sed -i "s|rancher/mirrored-pause:latest|rancher/mirrored-pause:${PAUSE_TAG}|g" \
                    "${CONTAINERD_CONFIG}"
                info "  → containerd config patched"
                break
            fi
            sleep 2
            CONTAINERD_WAIT=$((CONTAINERD_WAIT + 2))
        done

        # Patch pod manifests — wait for files to be generated
        info "Waiting for pod manifests to be generated..."
        MANIFEST_WAIT=0
        while [ $MANIFEST_WAIT -lt 60 ]; do
            if ls "${MANIFESTS_DIR}"/*.yaml > /dev/null 2>&1; then
                for f in "${MANIFESTS_DIR}"/*.yaml; do
                    [ -f "$f" ] || continue
                    sed -i \
                        -e "s|rancher/hardened-kubernetes:latest|rancher/hardened-kubernetes:${K8S_TAG}|g" \
                        -e "s|rancher/hardened-etcd:latest|rancher/hardened-etcd:${ETCD_TAG}|g" \
                        "$f"
                done
                info "  → pod manifests patched"
                break
            fi
            sleep 2
            MANIFEST_WAIT=$((MANIFEST_WAIT + 2))
        done

        info "  → Image tags patched"

        # Restart to apply patches
        info "Restarting OKE server to apply patches..."
        systemctl restart "${UNIT_NAME}.service"
    fi

    # Done
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  ✅  OKE ${OKE_VERSION} installed successfully!"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Status:  systemctl status ${UNIT_NAME}"
    echo "  Logs:    journalctl -u ${UNIT_NAME} -f"
    echo "  Config:  ${OKE_CONFIG_DIR}/config.yaml"
    echo ""
    if [ "$ROLE" = "server" ]; then
        echo "  Join a node:"
        echo "    curl -sfL https://get.openkubes.ai | \\"
        echo "      OKE_URL=https://<server-ip>:9345 \\"
        echo "      OKE_TOKEN=\$(cat ${OKE_DATA_DIR}/server/node-token) \\"
        echo "      sh -s - agent"
        echo ""
    fi
    if [ "$IS_OK_LINUX" = "true" ]; then
        echo "  ok-linux native features: KubeVirt + eBPF enabled"
        echo ""
    fi
}

main "$@"
