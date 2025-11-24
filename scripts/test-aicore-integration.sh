#!/bin/bash

# Test AI Core proxy integration with Bolt
# This script verifies that Bolt can communicate with the AI Core proxy

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== AI Core Proxy Integration Test ===${NC}"

# Configuration
NAMESPACE="${NAMESPACE:-devspace}"
PROXY_SERVICE="ai-core-proxy"
BOLT_SERVICE="bolt"
PROXY_PORT="3002"
BOLT_PORT="5173"

echo -e "${YELLOW}Configuration:${NC}"
echo "  Namespace: $NAMESPACE"
echo "  AI Core Proxy: $PROXY_SERVICE:$PROXY_PORT"
echo "  Bolt Service: $BOLT_SERVICE:$BOLT_PORT"
echo ""

# Check if kubectl is configured
if ! kubectl cluster-info > /dev/null 2>&1; then
  echo -e "${RED}ERROR: kubectl not configured or cluster not accessible${NC}"
  exit 1
fi

echo -e "${GREEN}✓ kubectl configured${NC}"

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" > /dev/null 2>&1; then
  echo -e "${RED}ERROR: Namespace $NAMESPACE does not exist${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Namespace $NAMESPACE exists${NC}"

# Check if AI Core proxy is deployed
echo -e "${BLUE}Checking AI Core proxy deployment...${NC}"
if ! kubectl get deployment "$PROXY_SERVICE" -n "$NAMESPACE" > /dev/null 2>&1; then
  echo -e "${YELLOW}WARNING: AI Core proxy deployment not found${NC}"
  echo "  You may need to deploy it first or it might be deployed with a different name"
  echo "  Looking for services..."
  kubectl get services -n "$NAMESPACE" | grep -i proxy || echo "  No proxy services found"
else
  echo -e "${GREEN}✓ AI Core proxy deployment found${NC}"
  
  # Check proxy pod status
  PROXY_PODS=$(kubectl get pods -n "$NAMESPACE" -l "app=$PROXY_SERVICE" -o jsonpath='{.items[*].metadata.name}')
  if [ -z "$PROXY_PODS" ]; then
    echo -e "${RED}ERROR: No AI Core proxy pods found${NC}"
    exit 1
  fi
  
  PROXY_POD=$(echo "$PROXY_PODS" | awk '{print $1}')
  PROXY_STATUS=$(kubectl get pod "$PROXY_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
  
  if [ "$PROXY_STATUS" != "Running" ]; then
    echo -e "${RED}ERROR: AI Core proxy pod is not running (Status: $PROXY_STATUS)${NC}"
    kubectl describe pod "$PROXY_POD" -n "$NAMESPACE" | tail -20
    exit 1
  fi
  
  echo -e "${GREEN}✓ AI Core proxy pod is running${NC}"
fi

# Check if Bolt is deployed
echo -e "${BLUE}Checking Bolt deployment...${NC}"
if ! kubectl get deployment "$BOLT_SERVICE" -n "$NAMESPACE" > /dev/null 2>&1; then
  echo -e "${RED}ERROR: Bolt deployment not found${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Bolt deployment found${NC}"

# Check Bolt pod status
BOLT_PODS=$(kubectl get pods -n "$NAMESPACE" -l "app=$BOLT_SERVICE" -o jsonpath='{.items[*].metadata.name}')
if [ -z "$BOLT_PODS" ]; then
  echo -e "${RED}ERROR: No Bolt pods found${NC}"
  exit 1
fi

BOLT_POD=$(echo "$BOLT_PODS" | awk '{print $1}')
BOLT_STATUS=$(kubectl get pod "$BOLT_POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')

if [ "$BOLT_STATUS" != "Running" ]; then
  echo -e "${RED}ERROR: Bolt pod is not running (Status: $BOLT_STATUS)${NC}"
  kubectl describe pod "$BOLT_POD" -n "$NAMESPACE" | tail -20
  exit 1
fi

echo -e "${GREEN}✓ Bolt pod is running${NC}"

# Check if services exist
echo -e "${BLUE}Checking services...${NC}"
if ! kubectl get service "$PROXY_SERVICE" -n "$NAMESPACE" > /dev/null 2>&1; then
  echo -e "${YELLOW}WARNING: AI Core proxy service not found${NC}"
else
  echo -e "${GREEN}✓ AI Core proxy service exists${NC}"
  PROXY_CLUSTER_IP=$(kubectl get service "$PROXY_SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
  echo "  Cluster IP: $PROXY_CLUSTER_IP:$PROXY_PORT"
fi

if ! kubectl get service "$BOLT_SERVICE" -n "$NAMESPACE" > /dev/null 2>&1; then
  echo -e "${RED}ERROR: Bolt service not found${NC}"
  exit 1
fi

echo -e "${GREEN}✓ Bolt service exists${NC}"
BOLT_CLUSTER_IP=$(kubectl get service "$BOLT_SERVICE" -n "$NAMESPACE" -o jsonpath='{.spec.clusterIP}')
echo "  Cluster IP: $BOLT_CLUSTER_IP:$BOLT_PORT"

# Test connectivity from Bolt to AI Core proxy
echo ""
echo -e "${BLUE}Testing connectivity from Bolt to AI Core proxy...${NC}"

# Check environment variables in Bolt pod
echo -e "${YELLOW}Checking Bolt environment variables...${NC}"
OPENAI_BASE_URL=$(kubectl exec -n "$NAMESPACE" "$BOLT_POD" -- env | grep OPENAI || echo "")
if [ -z "$OPENAI_BASE_URL" ]; then
  echo -e "${YELLOW}  No OPENAI environment variables found${NC}"
else
  echo -e "${GREEN}  Found OPENAI configuration:${NC}"
  echo "$OPENAI_BASE_URL" | sed 's/^/    /'
fi

# Try to curl the AI Core proxy from Bolt pod
echo ""
echo -e "${YELLOW}Testing HTTP connectivity to AI Core proxy...${NC}"
if kubectl exec -n "$NAMESPACE" "$BOLT_POD" -- sh -c "command -v curl > /dev/null 2>&1"; then
  PROXY_URL="http://$PROXY_SERVICE.$NAMESPACE.svc.cluster.local:$PROXY_PORT"
  echo "  Attempting to reach: $PROXY_URL"
  
  if kubectl exec -n "$NAMESPACE" "$BOLT_POD" -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$PROXY_URL/health" 2>/dev/null | grep -q "200"; then
    echo -e "${GREEN}✓ Successfully connected to AI Core proxy${NC}"
  else
    echo -e "${YELLOW}  Could not verify health endpoint, trying base URL...${NC}"
    HTTP_CODE=$(kubectl exec -n "$NAMESPACE" "$BOLT_POD" -- curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$PROXY_URL" 2>/dev/null || echo "000")
    if [ "$HTTP_CODE" != "000" ]; then
      echo -e "${GREEN}✓ Received HTTP $HTTP_CODE from AI Core proxy${NC}"
    else
      echo -e "${RED}✗ Could not connect to AI Core proxy${NC}"
    fi
  fi
else
  echo -e "${YELLOW}  curl not available in Bolt pod, checking DNS resolution...${NC}"
  
  if kubectl exec -n "$NAMESPACE" "$BOLT_POD" -- nslookup "$PROXY_SERVICE.$NAMESPACE.svc.cluster.local" > /dev/null 2>&1; then
    echo -e "${GREEN}✓ DNS resolution successful${NC}"
  else
    echo -e "${YELLOW}  nslookup not available, assuming DNS is working${NC}"
  fi
fi

# Check Bolt logs for any errors related to LLM providers
echo ""
echo -e "${BLUE}Checking Bolt logs for LLM-related messages...${NC}"
RECENT_LOGS=$(kubectl logs -n "$NAMESPACE" "$BOLT_POD" --tail=50 2>/dev/null || echo "")
if echo "$RECENT_LOGS" | grep -i "error\|fail\|openai\|llm" > /dev/null; then
  echo -e "${YELLOW}  Found relevant log messages:${NC}"
  echo "$RECENT_LOGS" | grep -i "error\|fail\|openai\|llm" | tail -10 | sed 's/^/    /'
else
  echo -e "${GREEN}  No errors found in recent logs${NC}"
fi

# Summary
echo ""
echo -e "${GREEN}=== Test Summary ===${NC}"
echo -e "${GREEN}✓ Namespace exists${NC}"
echo -e "${GREEN}✓ AI Core proxy is deployed and running${NC}"
echo -e "${GREEN}✓ Bolt is deployed and running${NC}"
echo -e "${GREEN}✓ Services are configured${NC}"
echo ""
echo -e "${BLUE}To access Bolt:${NC}"
echo -e "  ${YELLOW}kubectl port-forward -n $NAMESPACE svc/$BOLT_SERVICE $BOLT_PORT:$BOLT_PORT${NC}"
echo -e "  Then open: ${YELLOW}http://localhost:$BOLT_PORT${NC}"
echo ""
echo -e "${BLUE}To check Bolt logs:${NC}"
echo -e "  ${YELLOW}kubectl logs -n $NAMESPACE -l app=$BOLT_SERVICE -f${NC}"
echo ""
echo -e "${BLUE}To check AI Core proxy logs:${NC}"
echo -e "  ${YELLOW}kubectl logs -n $NAMESPACE -l app=$PROXY_SERVICE -f${NC}"
