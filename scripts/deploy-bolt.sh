#!/bin/bash

# Deploy Bolt AI Agent to Kubernetes using Helm
# This script requires the following environment variables:
# - KUBE_TOKEN: Kubernetes authentication token
# - DOCKER_USERNAME: Docker registry username (optional for local images)
# - DOCKER_PASSWORD: Docker registry password (optional for local images)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Bolt AI Agent Deployment Script ===${NC}"

# Check required environment variables
if [ -z "$KUBE_TOKEN" ]; then
  echo -e "${RED}ERROR: KUBE_TOKEN environment variable is not set${NC}"
  exit 1
fi

# Set defaults
NAMESPACE="${NAMESPACE:-devspace}"
RELEASE_NAME="${RELEASE_NAME:-bolt}"
KUBE_USER="${KUBE_USER:-deployer}"
KUBE_CLUSTER="${KUBE_CLUSTER:-kubernetes}"
KUBE_SERVER="${KUBE_SERVER:-https://kubernetes.default.svc}"
HELM_CHART_PATH="${HELM_CHART_PATH:-./helm/bolt}"
IMAGE_TAG="${IMAGE_TAG:-production}"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Namespace: $NAMESPACE"
echo "  Release: $RELEASE_NAME"
echo "  Kube User: $KUBE_USER"
echo "  Kube Cluster: $KUBE_CLUSTER"
echo "  Chart Path: $HELM_CHART_PATH"
echo "  Image Tag: $IMAGE_TAG"
echo ""

# Configure kubectl
echo -e "${GREEN}Configuring kubectl...${NC}"
kubectl config set-cluster "$KUBE_CLUSTER" --server="$KUBE_SERVER" --insecure-skip-tls-verify=true
kubectl config set-credentials "$KUBE_USER" --token="$KUBE_TOKEN"
kubectl config set-context "$KUBE_CLUSTER" --cluster="$KUBE_CLUSTER" --user="$KUBE_USER" --namespace="$NAMESPACE"
kubectl config use-context "$KUBE_CLUSTER"

# Verify connection
echo -e "${GREEN}Verifying connection...${NC}"
if ! kubectl cluster-info > /dev/null 2>&1; then
  echo -e "${RED}ERROR: Failed to connect to Kubernetes cluster${NC}"
  exit 1
fi
echo -e "${GREEN}✓ Connected to Kubernetes cluster${NC}"

# Create namespace if it doesn't exist
echo -e "${GREEN}Creating namespace if it doesn't exist...${NC}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
  echo -e "${YELLOW}Helm not found, installing...${NC}"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Lint Helm chart
echo -e "${GREEN}Linting Helm chart...${NC}"
helm lint "$HELM_CHART_PATH"

# Prepare Helm values
HELM_VALUES="--set image.tag=$IMAGE_TAG"

# Add Docker registry credentials if provided
if [ -n "$DOCKER_USERNAME" ] && [ -n "$DOCKER_PASSWORD" ]; then
  echo -e "${GREEN}Creating Docker registry secret...${NC}"
  kubectl create secret docker-registry docker-registry-secret \
    --docker-server="${DOCKER_REGISTRY:-docker.io}" \
    --docker-username="$DOCKER_USERNAME" \
    --docker-password="$DOCKER_PASSWORD" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
  
  HELM_VALUES="$HELM_VALUES --set imagePullSecrets[0].name=docker-registry-secret"
fi

# Deploy with Helm
echo -e "${GREEN}Deploying Helm chart...${NC}"
helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_PATH" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  $HELM_VALUES \
  --wait \
  --timeout 10m

echo -e "${GREEN}✓ Helm chart deployed successfully${NC}"

# Check deployment status
echo -e "${GREEN}Checking deployment status...${NC}"
kubectl rollout status deployment/bolt -n "$NAMESPACE" --timeout=5m

# Get service information
echo -e "${BLUE}=== Service Information ===${NC}"
kubectl get service bolt -n "$NAMESPACE"

# Get pod information
echo -e "${BLUE}=== Pod Information ===${NC}"
kubectl get pods -n "$NAMESPACE" -l app=bolt

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo -e "${YELLOW}Service URL:${NC} http://bolt.$NAMESPACE.svc.cluster.local:5173"
echo -e "${YELLOW}To check logs:${NC} kubectl logs -n $NAMESPACE -l app=bolt -f"
echo -e "${YELLOW}To port-forward:${NC} kubectl port-forward -n $NAMESPACE svc/bolt 5173:5173"
echo ""
echo -e "${BLUE}To access Bolt locally, run:${NC}"
echo -e "${YELLOW}  kubectl port-forward -n $NAMESPACE svc/bolt 5173:5173${NC}"
echo -e "${BLUE}Then open:${NC} ${YELLOW}http://localhost:5173${NC}"
