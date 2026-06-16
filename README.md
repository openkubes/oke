## Quick Start

```bash
# Install server
curl -sfL https://raw.githubusercontent.com/openkubes/oke/main/install.sh | \
  sudo OKE_VERSION=v1.35.5+oke2r4 sh -s - server

# Set up kubectl
mkdir -p ~/.kube
sudo cp /etc/rancher/oke/oke.yaml ~/.kube/config
sudo chown $USER ~/.kube/config
export KUBECONFIG=~/.kube/config

# Verify
oke --version
kubectl get nodes
```

```bash
# Join a worker node
curl -sfL https://raw.githubusercontent.com/openkubes/oke/main/install.sh | \
  sudo OKE_URL=https://<server-ip>:9345 \
  OKE_TOKEN=$(cat /var/lib/openkubes/oke/server/node-token) \
  sh -s - agent
```

> Full installation guide: [INSTALL.md](./INSTALL.md)

