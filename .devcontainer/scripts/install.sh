#!/bin/bash
set -euo pipefail

echo "================================================"
echo "  Installing Istio ambient tooling"
echo "================================================"

# ── k3d ──────────────────────────────────────────────────────────────────────
if command -v k3d &>/dev/null; then
  echo "▶ k3d already installed ($(k3d version | head -1 | awk '{print $3}'))"
else
  echo "▶ Installing k3d..."
  curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
  echo "  ✅ k3d $(k3d version | head -1 | awk '{print $3}') installed"
fi

# ── istioctl ─────────────────────────────────────────────────────────────────
if command -v istioctl &>/dev/null; then
  echo "▶ istioctl already installed ($(istioctl version --remote=false 2>/dev/null | head -1))"
else
  echo "▶ Downloading Istio..."
  ISTIO_VERSION="1.30.0"   # pin for reproducibility; bump when you want a newer mesh
  curl -sL "https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-linux-amd64.tar.gz" \
    -o /tmp/istio.tar.gz
  tar -xzf /tmp/istio.tar.gz -C /tmp
  sudo mv "/tmp/istio-${ISTIO_VERSION}" /opt/istio
  sudo ln -sf /opt/istio/bin/istioctl /usr/local/bin/istioctl
  rm -f /tmp/istio.tar.gz
  echo "  ✅ istioctl $(istioctl version --remote=false 2>/dev/null | head -1) installed"
fi

# ── jq (useful for parsing kubectl output) ───────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "▶ Installing jq..."
  sudo apt-get update -qq && sudo apt-get install -y jq >/dev/null
  echo "  ✅ jq installed"
fi

echo ""
echo "✅ Tooling installation complete."
echo "   Run 'bash .devcontainer/scripts/start-cluster.sh' to bring up the cluster."