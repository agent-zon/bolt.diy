#!/bin/bash

# Deploy Bolt + AI Core Proxy together using Helm
# This script deploys both services in a single Helm release

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== Bolt + AI Core Proxy Combined Deployment ===${NC}"

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
echo "  Chart Path: $HELM_CHART_PATH"
echo "  Bolt Image Tag: $IMAGE_TAG"
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

# Create namespace
echo -e "${GREEN}Creating namespace...${NC}"
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
  echo -e "${YELLOW}Helm not found, installing...${NC}"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Lint Helm chart
echo -e "${GREEN}Linting Helm chart...${NC}"
helm lint "$HELM_CHART_PATH"

# Create Docker registry secret for AI Core proxy image
if [ -n "$DOCKER_USERNAME" ] && [ -n "$DOCKER_PASSWORD" ]; then
  echo -e "${GREEN}Creating Docker registry secret for AI Core proxy...${NC}"
  kubectl create secret docker-registry docker-registry-secret \
    --docker-server="${DOCKER_REGISTRY:-scai-dev.common.repositories.cloud.sap}" \
    --docker-username="$DOCKER_USERNAME" \
    --docker-password="$DOCKER_PASSWORD" \
    --namespace="$NAMESPACE" \
    --dry-run=client -o yaml | kubectl apply -f -
  
  echo -e "${GREEN}✓ Docker registry secret created${NC}"
fi

# Prepare Helm values
HELM_VALUES="--set image.tag=$IMAGE_TAG"
HELM_VALUES="$HELM_VALUES --set aiCoreProxy.enabled=true"

# Add Docker registry credentials for AI Core proxy
if [ -n "$DOCKER_USERNAME" ] && [ -n "$DOCKER_PASSWORD" ]; then
  HELM_VALUES="$HELM_VALUES --set aiCoreProxy.imagePullSecrets[0].name=docker-registry-secret"
  HELM_VALUES="$HELM_VALUES --set dockerRegistry.username=$DOCKER_USERNAME"
  HELM_VALUES="$HELM_VALUES --set dockerRegistry.password=$DOCKER_PASSWORD"
fi

# Deploy with combined values
echo -e "${GREEN}Deploying Bolt + AI Core Proxy...${NC}"
helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_PATH" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  -f "$HELM_CHART_PATH/values-combined.yaml" \
  $HELM_VALUES \
  --wait \
  --timeout 10m

echo -e "${GREEN}✓ Helm chart deployed successfully${NC}"

# Check deployment status
echo -e "${GREEN}Checking deployment status...${NC}"

echo -e "${YELLOW}Waiting for AI Core Proxy...${NC}"
kubectl rollout status deployment/ai-core-proxy -n "$NAMESPACE" --timeout=5m

echo -e "${YELLOW}Waiting for Bolt...${NC}"
kubectl rollout status deployment/bolt -n "$NAMESPACE" --timeout=5m

# Get service information
echo ""
echo -e "${BLUE}=== Deployment Summary ===${NC}"
echo ""
echo -e "${GREEN}AI Core Proxy:${NC}"
kubectl get service ai-core-proxy -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE" -l app=ai-core-proxy

echo ""
echo -e "${GREEN}Bolt:${NC}"
kubectl get service bolt -n "$NAMESPACE"
kubectl get pods -n "$NAMESPACE" -l app=bolt

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo ""
echo -e "${YELLOW}AI Core Proxy URL:${NC} http://ai-core-proxy.$NAMESPACE.svc.cluster.local:3002"
echo -e "${YELLOW}Bolt URL:${NC} http://bolt.$NAMESPACE.svc.cluster.local:5173"
echo ""
echo -e "${BLUE}To access Bolt locally:${NC}"
echo -e "  ${YELLOW}kubectl port-forward -n $NAMESPACE svc/bolt 5173:5173${NC}"
echo -e "  ${BLUE}Then open:${NC} ${YELLOW}http://localhost:5173${NC}"
echo ""
echo -e "${BLUE}To check logs:${NC}"
echo -e "  ${YELLOW}Bolt:${NC} kubectl logs -n $NAMESPACE -l app=bolt -f"
echo -e "  ${YELLOW}AI Core Proxy:${NC} kubectl logs -n $NAMESPACE -l app=ai-core-proxy -f"
echo ""
echo -e "${BLUE}To test the integration:${NC}"
echo -e "  ${YELLOW}./scripts/test-aicore-integration.sh${NC}"
