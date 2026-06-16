# OKE Installation Guide

> **OKE** (OpenKubes Kubernetes Engine) `v1.35.5+oke2r4`  
> Kubernetes 1.35.5 · Go 1.25.9 · BoringCrypto · Ubuntu 24.04 LTS

---

## Prerequisites

| Resource | Minimum |
|----------|---------|
| OS | Ubuntu 22.04 / 24.04 LTS (amd64 or arm64) |
| CPU | 4 cores |
| RAM | 8 GB |
| Disk | 40 GB |
| Network | Outbound HTTPS (GitHub, Docker Hub) |

---

## Server Installation

```bash
curl -sfL https://raw.githubusercontent.com/openkubes/oke/main/install.sh | \
  sudo OKE_VERSION=v1.35.5+oke2r4 sh -s - server
```

The installer will:
- Download and verify the OKE binary to `/usr/local/bin/oke`
- Create a `kubectl` symlink at `/usr/local/bin/kubectl`
- Write default config to `/etc/openkubes/oke/config.yaml`
- Write and enable systemd unit `oke-server.service`
- Wait 30s for initialization, patch image tags and restart

Expected output:
```
✅  OKE v1.35.5+oke2r4 installed successfully!

  Status:  systemctl status oke-server
  Logs:    journalctl -u oke-server -f
  Config:  /etc/openkubes/oke/config.yaml
```

---

## Configure kubectl

After installation, set up `kubectl` access:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/oke/oke.yaml ~/.kube/config
sudo chown $USER ~/.kube/config
export KUBECONFIG=~/.kube/config
```

> **Note:** Add `export KUBECONFIG=~/.kube/config` to your `~/.bashrc` or `~/.zshrc`
> to make it permanent.

Verify:

```bash
oke --version
# oke version v1.35.5+oke2r4 (3c50d1f)
# go version go1.25.9 X:boringcrypto

kubectl get nodes
# NAME        STATUS   ROLES                AGE   VERSION
# oke-local   Ready    control-plane,etcd   2m    v1.35.5+rke2r2
```

> **Note:** The node `VERSION` column currently shows `v1.35.5+rke2r2` — this comes
> from the upstream `rancher/rke2-runtime` image. This will be resolved in Sprint 3
> when OKE builds its own runtime image at `ghcr.io/openkubes/oke-runtime`.

---

## Join an Agent Node

On the agent node:

```bash
# Get the server token from the server node
OKE_TOKEN=$(cat /var/lib/openkubes/oke/server/node-token)

# Run on the agent node
curl -sfL https://raw.githubusercontent.com/openkubes/oke/main/install.sh | \
  sudo OKE_URL=https://<server-ip>:9345 \
  OKE_TOKEN=<token> \
  sh -s - agent
```

---

## Key Paths

| Path | Description |
|------|-------------|
| `/usr/local/bin/oke` | OKE binary |
| `/usr/local/bin/kubectl` | kubectl symlink → oke |
| `/etc/openkubes/oke/config.yaml` | OKE server config |
| `/etc/rancher/oke/oke.yaml` | kubeconfig (root-owned) |
| `/var/lib/openkubes/oke/server/node-token` | Node join token |
| `/etc/systemd/system/oke-server.service` | systemd unit |

---

## Useful Commands

```bash
# Service status
systemctl status oke-server

# Live logs
journalctl -u oke-server -f

# Node status
kubectl get nodes -w

# All pods
kubectl get pods -A

# OKE version
oke --version
```

---

## Known Issues

| Issue | Status | Fix |
|-------|--------|-----|
| Node VERSION shows `rke2r2` | ⚠️ Sprint 3 | Own runtime image at `ghcr.io/openkubes/oke-runtime` |
| `kubectl` needs `export KUBECONFIG` | ⚠️ Sprint 3 | `--write-kubeconfig-mode 644` in install.sh |
| CCM loop warning in logs | ⚠️ Sprint 4 | Cloud-Provider Taint Fix |
| No uninstall script | ⚠️ Sprint 3 | `oke-uninstall.sh` |

---

## Uninstall (manual)

Until an uninstall script is available:

```bash
sudo systemctl stop oke-server
sudo systemctl disable oke-server
sudo rm -f /etc/systemd/system/oke-server.service
sudo rm -f /usr/local/bin/oke /usr/local/bin/kubectl
sudo rm -rf /etc/rancher /etc/openkubes
sudo rm -rf /var/lib/rancher /var/lib/openkubes
sudo systemctl daemon-reload
```
