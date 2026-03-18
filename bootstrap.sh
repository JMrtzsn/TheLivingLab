#!/usr/bin/env bash
#
# bootstrap.sh - Bring up the Minimal Viable Platform
#
# Usage: ./bootstrap.sh
#
# This script:
#   1. Provisions a Kind cluster via Terraform
#   2. Installs NGINX Ingress Controller (direct Helm - needed before ArgoCD Ingress works)
#   3. Installs ArgoCD (direct Helm - the "chicken" that manages everything else)
#   4. Applies the App-of-Apps root Application (ArgoCD takes over from here)
#
# Teardown: terraform -chdir=terraform destroy -auto-approve

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="${SCRIPT_DIR}/terraform"
APPS_DIR="${SCRIPT_DIR}/apps"
PLATFORM_DIR="${SCRIPT_DIR}/platform"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# ---------------------------------------------------------------------------
# Pre-flight checks
# ---------------------------------------------------------------------------
info "Running pre-flight checks..."

for cmd in terraform kind kubectl helm docker; do
  command -v "$cmd" >/dev/null 2>&1 || error "'$cmd' is not installed. Please install it first."
done

docker info >/dev/null 2>&1 || error "Docker is not running. Please start Docker Desktop."

ok "All prerequisites found."

# ---------------------------------------------------------------------------
# Step 1: Provision Kind cluster via Terraform
# ---------------------------------------------------------------------------
info "Step 1/6: Provisioning Kind cluster via Terraform..."

terraform -chdir="$TERRAFORM_DIR" init -input=false
terraform -chdir="$TERRAFORM_DIR" apply -auto-approve -input=false

KUBECONFIG_PATH=$(terraform -chdir="$TERRAFORM_DIR" output -raw kubeconfig_path)
export KUBECONFIG="$KUBECONFIG_PATH"

ok "Kind cluster provisioned. KUBECONFIG=$KUBECONFIG_PATH"

# ---------------------------------------------------------------------------
# Step 2: Wait for nodes to be ready
# ---------------------------------------------------------------------------
info "Step 2/6: Waiting for cluster nodes to be ready..."

kubectl wait --for=condition=Ready nodes --all --timeout=120s
ok "All nodes are ready."

# ---------------------------------------------------------------------------
# Step 3: Install NGINX Ingress Controller via Helm
# ---------------------------------------------------------------------------
info "Step 3/6: Installing NGINX Ingress Controller..."

helm repo add ingress-nginx https://kubernetes.github.io/ingress-nginx 2>/dev/null || true
helm repo update ingress-nginx

helm upgrade --install ingress-nginx ingress-nginx/ingress-nginx \
  --namespace ingress-nginx \
  --create-namespace \
  --values "${PLATFORM_DIR}/ingress-nginx/values.yaml" \
  --wait \
  --timeout 5m

ok "NGINX Ingress Controller installed."

# ---------------------------------------------------------------------------
# Step 4: Install ArgoCD via Helm
# ---------------------------------------------------------------------------
info "Step 4/6: Installing ArgoCD..."

helm repo add argo https://argoproj.github.io/argo-helm 2>/dev/null || true
helm repo update argo

helm upgrade --install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values "${PLATFORM_DIR}/argocd/values.yaml" \
  --wait \
  --timeout 5m

ok "ArgoCD installed."

# ---------------------------------------------------------------------------
# Step 5: Wait for ArgoCD to be fully ready
# ---------------------------------------------------------------------------
info "Step 5/6: Waiting for ArgoCD server to be ready..."

kubectl -n argocd rollout status deployment/argocd-server --timeout=120s
ok "ArgoCD server is ready."

# ---------------------------------------------------------------------------
# Step 6: Apply App-of-Apps root Application
# ---------------------------------------------------------------------------
info "Step 6/6: Applying App-of-Apps root Application..."

# Note: The root-app points to git@github.com:JMrtzsn/TheLivingLab.git
# Make sure you've pushed this repo before ArgoCD tries to sync.
# ArgoCD will show "ComparisonError" until the repo is accessible.
kubectl apply -f "${APPS_DIR}/root-app.yaml"

ok "Root Application applied. ArgoCD will now manage all platform services."

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo -e "${GREEN}============================================================${NC}"
echo -e "${GREEN}  Minimal Viable Platform is UP                            ${NC}"
echo -e "${GREEN}============================================================${NC}"
echo ""
echo -e "  ${CYAN}KUBECONFIG:${NC}  export KUBECONFIG=${KUBECONFIG_PATH}"
echo ""
echo -e "  ${CYAN}ArgoCD UI:${NC}   https://argocd.localhost"
echo -e "  ${CYAN}  Username:${NC}  admin"
echo -e "  ${CYAN}  Password:${NC}  Run: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d && echo"
echo ""
echo -e "  ${CYAN}Grafana:${NC}     http://grafana.localhost"
echo -e "  ${CYAN}  Login:${NC}     admin / admin"
echo ""
echo -e "  ${CYAN}Prometheus:${NC}  http://prometheus.localhost"
echo ""
echo -e "  ${YELLOW}Note:${NC} Grafana and Prometheus are deployed by ArgoCD via GitOps."
echo -e "  ${YELLOW}      They will appear once ArgoCD syncs the monitoring app.${NC}"
echo -e "  ${YELLOW}      This requires the Git repo to be pushed and accessible.${NC}"
echo ""
echo -e "  ${CYAN}Teardown:${NC}    terraform -chdir=terraform destroy -auto-approve"
echo ""
echo -e "${GREEN}============================================================${NC}"
