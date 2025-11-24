#!/bin/bash

# Deploy AI Core Proxy to Kubernetes using Helm
# This script requires the following environment variables:
# - KUBE_TOKEN: Kubernetes authentication token
# - KUBE_USER: Kubernetes user (optional, defaults to 'deployer')
# - DOCKER_USERNAME: Docker registry username
# - DOCKER_PASSWORD: Docker registry password
# - DOCKER_REGISTRY: Docker registry URL
# - AI_CORE_KEY: AI Core API key (optional)

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== AI Core Proxy Deployment Script ===${NC}"

# Check required environment variables
if [ -z "$KUBE_TOKEN" ]; then
  echo -e "${RED}ERROR: KUBE_TOKEN environment variable is not set${NC}"
  exit 1
fi

if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
  echo -e "${RED}ERROR: DOCKER_USERNAME and DOCKER_PASSWORD must be set${NC}"
  exit 1
fi

# Set defaults
NAMESPACE="${NAMESPACE:-devspace}"
RELEASE_NAME="${RELEASE_NAME:-ai-core-proxy}"
KUBE_USER="${KUBE_USER:-deployer}"
KUBE_CLUSTER="${KUBE_CLUSTER:-kubernetes}"
KUBE_SERVER="${KUBE_SERVER:-https://kubernetes.default.svc}"
HELM_CHART_PATH="${HELM_CHART_PATH:-./helm/ai-core-proxy}"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Namespace: $NAMESPACE"
echo "  Release: $RELEASE_NAME"
echo "  Kube User: $KUBE_USER"
echo "  Kube Cluster: $KUBE_CLUSTER"
echo "  Chart Path: $HELM_CHART_PATH"
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

# Create docker registry secret
echo -e "${GREEN}Creating Docker registry secret...${NC}"
kubectl create secret docker-registry docker-registry-secret \
  --docker-server="${DOCKER_REGISTRY:-scai-dev.common.repositories.cloud.sap}" \
  --docker-username="$DOCKER_USERNAME" \
  --docker-password="$DOCKER_PASSWORD" \
  --namespace="$NAMESPACE" \
  --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}✓ Docker registry secret created${NC}"

# Install or upgrade Helm chart
echo -e "${GREEN}Deploying Helm chart...${NC}"

# Check if Helm is installed
if ! command -v helm &> /dev/null; then
  echo -e "${YELLOW}Helm not found, installing...${NC}"
  curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi

# Prepare Helm values
HELM_VALUES=""
if [ -n "$DOCKER_USERNAME" ]; then
  HELM_VALUES="$HELM_VALUES --set dockerRegistry.username=$DOCKER_USERNAME"
fi
if [ -n "$DOCKER_PASSWORD" ]; then
  HELM_VALUES="$HELM_VALUES --set dockerRegistry.password=$DOCKER_PASSWORD"
fi
if [ -n "$DOCKER_REGISTRY" ]; then
  HELM_VALUES="$HELM_VALUES --set image.repository=$DOCKER_REGISTRY/aap/sap-ai-proxy"
fi

# Deploy with Helm
helm upgrade --install "$RELEASE_NAME" "$HELM_CHART_PATH" \
  --namespace "$NAMESPACE" \
  --create-namespace \
  $HELM_VALUES \
  --wait \
  --timeout 5m

echo -e "${GREEN}✓ Helm chart deployed successfully${NC}"

# Check deployment status
echo -e "${GREEN}Checking deployment status...${NC}"
kubectl rollout status deployment/ai-core-proxy -n "$NAMESPACE" --timeout=5m

# Get service information
echo -e "${GREEN}Service Information:${NC}"
kubectl get service ai-core-proxy -n "$NAMESPACE"

# Get pod information
echo -e "${GREEN}Pod Information:${NC}"
kubectl get pods -n "$NAMESPACE" -l app=ai-core-proxy

echo ""
echo -e "${GREEN}=== Deployment Complete ===${NC}"
echo -e "${YELLOW}Service URL:${NC} http://ai-core-proxy.$NAMESPACE.svc.cluster.local:3002"
echo -e "${YELLOW}To check logs:${NC} kubectl logs -n $NAMESPACE -l app=ai-core-proxy -f"
echo -e "${YELLOW}To port-forward:${NC} kubectl port-forward -n $NAMESPACE svc/ai-core-proxy 3002:3002"
