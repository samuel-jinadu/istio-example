#!/bin/bash
set -euo pipefail

CLUSTER_NAME="istio-ambient"
ISTIO_VERSION="1.30.0"

echo "================================================"
echo "  Starting k3d cluster: ${CLUSTER_NAME}"
echo "================================================"

# ── 1. Create k3d cluster (Traefik disabled) ─────────────────────────────────
if k3d cluster list 2>/dev/null | grep -q "^${CLUSTER_NAME}"; then
  echo "▶ Cluster '${CLUSTER_NAME}' already exists – starting it if stopped..."
  k3d cluster start "${CLUSTER_NAME}" 2>/dev/null || true
else
  echo "▶ Creating k3d cluster '${CLUSTER_NAME}'..."
  k3d cluster create "${CLUSTER_NAME}" \
    --api-port 6550 \
    -p '9080:80@loadbalancer' \
    -p '9443:443@loadbalancer' \
    --agents 2 \
    --k3s-arg '--disable=traefik@server:*' \
    --wait
  echo "  ✅ Cluster created"
fi

k3d kubeconfig merge "${CLUSTER_NAME}" --kubeconfig-merge-default --kubeconfig-switch-context
kubectl wait --for=condition=Ready nodes --all --timeout=120s

# ── 2. Gateway API CRDs (experimental) ───────────────────────────────────────
echo "▶ Installing Gateway API experimental CRDs..."
kubectl apply --server-side -f \
  https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/experimental-install.yaml

# ── 3. Istio ambient (k3d CNI overrides) ────────────────────────────────────
echo "▶ Installing Istio ambient profile..."
istioctl install --set profile=ambient \
  --set values.cni.cniConfDir=/var/lib/rancher/k3s/agent/etc/cni/net.d \
  --set values.cni.cniBinDir=/bin \
  --skip-confirmation
kubectl -n istio-system rollout status deployment/istiod --timeout=180s
kubectl -n istio-system rollout status daemonset/ztunnel --timeout=180s
kubectl -n istio-system rollout status daemonset/istio-cni-node --timeout=180s
echo "✅ Istio ambient mesh ready."

# ── 4. Bookinfo (local manifests) ────────────────────────────────────────────
echo "▶ Applying Bookinfo from manifests/bookinfo.yaml..."
kubectl apply -f manifests/bookinfo.yaml
kubectl wait --for=condition=Ready pod -l app=productpage --timeout=120s
kubectl wait --for=condition=Ready pod -l app=details     --timeout=120s
kubectl wait --for=condition=Ready pod -l app=reviews     --timeout=120s
kubectl wait --for=condition=Ready pod -l app=ratings     --timeout=120s

# ── 5. Ambient enrollment + waypoint ────────────────────────────────────────
echo "▶ Enrolling namespace and applying waypoint..."
kubectl label namespace default istio.io/dataplane-mode=ambient --overwrite
kubectl apply -f manifests/waypoint.yaml
kubectl label namespace default istio.io/use-waypoint=waypoint --overwrite

# ── 6. Gateway (local manifest) ─────────────────────────────────────────────
echo "▶ Applying Gateway API gateway from manifests/bookinfo-gateway.yaml..."
kubectl apply -f manifests/bookinfo-gateway.yaml
kubectl wait --for=condition=Programmed gateway/bookinfo-gateway --timeout=180s

# ── 7. Prometheus (Istio addon — remote, large upstream bundle) ─────────────
echo "▶ Installing Prometheus addon..."
kubectl apply -f "https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/prometheus.yaml"
kubectl -n istio-system rollout status deployment/prometheus --timeout=180s

# ── 8. Kiali (Istio addon) ──────────────────────────────────────────────────
echo "▶ Installing Kiali addon..."
kubectl apply -f "https://raw.githubusercontent.com/istio/istio/${ISTIO_VERSION}/samples/addons/kiali.yaml"
kubectl -n istio-system rollout status deployment/kiali --timeout=180s

echo ""
echo "================================================"
echo "  ✅ Istio ambient environment ready!"
echo "================================================"
echo ""
echo "  Bookinfo:  http://localhost:9080/productpage"
echo "  Kiali:     istioctl dashboard kiali"
echo "  Prometheus: kubectl -n istio-system port-forward svc/prometheus 9090:9090"
echo ""
echo "  Verify ztunnel:  istioctl ztunnel-config workloads"
echo ""