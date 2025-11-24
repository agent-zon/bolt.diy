#!/bin/bash

# Validate Bolt Kubernetes Deployment Setup
# This script checks that all required files and configurations are in place

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${GREEN}=== Bolt Deployment Validation ===${NC}"
echo ""

ERRORS=0
WARNINGS=0

# Function to check file exists
check_file() {
  local file=$1
  local description=$2
  if [ -f "$file" ]; then
    echo -e "${GREEN}✓${NC} $description: $file"
  else
    echo -e "${RED}✗${NC} $description: $file ${RED}(missing)${NC}"
    ((ERRORS++))
  fi
}

# Function to check directory exists
check_dir() {
  local dir=$1
  local description=$2
  if [ -d "$dir" ]; then
    echo -e "${GREEN}✓${NC} $description: $dir"
  else
    echo -e "${RED}✗${NC} $description: $dir ${RED}(missing)${NC}"
    ((ERRORS++))
  fi
}

# Function to check command exists
check_command() {
  local cmd=$1
  local description=$2
  if command -v "$cmd" &> /dev/null; then
    local version=$($cmd version 2>&1 | head -n1 || echo "unknown")
    echo -e "${GREEN}✓${NC} $description: $cmd ${BLUE}($version)${NC}"
  else
    echo -e "${YELLOW}⚠${NC} $description: $cmd ${YELLOW}(not installed)${NC}"
    ((WARNINGS++))
  fi
}

# Function to check environment variable
check_env() {
  local var=$1
  local description=$2
  local required=$3
  if [ -n "${!var}" ]; then
    echo -e "${GREEN}✓${NC} $description: $var ${BLUE}(set)${NC}"
  else
    if [ "$required" = "true" ]; then
      echo -e "${RED}✗${NC} $description: $var ${RED}(not set - required)${NC}"
      ((ERRORS++))
    else
      echo -e "${YELLOW}⚠${NC} $description: $var ${YELLOW}(not set - optional)${NC}"
      ((WARNINGS++))
    fi
  fi
}

# Check Helm Chart Files
echo -e "${BLUE}=== Helm Chart Files ===${NC}"
check_file "helm/bolt/Chart.yaml" "Chart metadata"
check_file "helm/bolt/values.yaml" "Default values"
check_file "helm/bolt/values-aicore.yaml" "AI Core values (Phase 2)"
check_file "helm/bolt/values-combined.yaml" "Combined values (Phase 3)"
check_file "helm/bolt/README.md" "Helm README"
check_dir "helm/bolt/templates" "Templates directory"
echo ""

# Check Helm Templates
echo -e "${BLUE}=== Helm Templates ===${NC}"
check_file "helm/bolt/templates/_helpers.tpl" "Helper templates"
check_file "helm/bolt/templates/deployment.yaml" "Bolt deployment"
check_file "helm/bolt/templates/service.yaml" "Bolt service"
check_file "helm/bolt/templates/configmap.yaml" "Bolt config"
check_file "helm/bolt/templates/secret.yaml" "Bolt secrets"
check_file "helm/bolt/templates/serviceaccount.yaml" "Service account"
check_file "helm/bolt/templates/aicore-deployment.yaml" "AI Core proxy deployment"
check_file "helm/bolt/templates/aicore-service.yaml" "AI Core proxy service"
check_file "helm/bolt/templates/aicore-configmap.yaml" "AI Core proxy config"
echo ""

# Check Scripts
echo -e "${BLUE}=== Deployment Scripts ===${NC}"
check_file "scripts/deploy-bolt.sh" "Bolt deployment script"
check_file "scripts/deploy-combined.sh" "Combined deployment script"
check_file "scripts/test-aicore-integration.sh" "Integration test script"

# Check if scripts are executable
for script in scripts/deploy-bolt.sh scripts/deploy-combined.sh scripts/test-aicore-integration.sh; do
  if [ -x "$script" ]; then
    echo -e "${GREEN}✓${NC} Executable: $script"
  else
    echo -e "${YELLOW}⚠${NC} Not executable: $script ${YELLOW}(run: chmod +x $script)${NC}"
    ((WARNINGS++))
  fi
done
echo ""

# Check GitHub Actions Workflows
echo -e "${BLUE}=== GitHub Actions Workflows ===${NC}"
check_file ".github/workflows/deploy-bolt.yaml" "Bolt deployment workflow"
check_file ".github/workflows/deploy-combined.yaml" "Combined deployment workflow"
echo ""

# Check Documentation
echo -e "${BLUE}=== Documentation ===${NC}"
check_file "DEPLOYMENT.md" "Comprehensive deployment guide"
check_file "README-K8S.md" "Quick reference guide"
check_file "DEPLOYMENT-SUMMARY.md" "Implementation summary"
check_file "Dockerfile" "Dockerfile"
echo ""

# Check Required Commands
echo -e "${BLUE}=== Required Commands ===${NC}"
check_command "docker" "Docker"
check_command "kubectl" "kubectl"
check_command "helm" "Helm"
echo ""

# Check Optional Commands
echo -e "${BLUE}=== Optional Commands ===${NC}"
check_command "git" "Git"
check_command "curl" "curl"
echo ""

# Check Environment Variables (only if deploying)
if [ "${CHECK_ENV:-false}" = "true" ]; then
  echo -e "${BLUE}=== Environment Variables ===${NC}"
  check_env "KUBE_TOKEN" "Kubernetes token" "true"
  check_env "KUBE_SERVER" "Kubernetes server" "false"
  check_env "DOCKER_USERNAME" "Docker username (for Phase 3)" "false"
  check_env "DOCKER_PASSWORD" "Docker password (for Phase 3)" "false"
  echo ""
fi

# Summary
echo -e "${BLUE}=== Validation Summary ===${NC}"
if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
  echo -e "${GREEN}✓ All checks passed!${NC}"
  echo ""
  echo -e "${GREEN}Your deployment setup is ready!${NC}"
  echo ""
  echo -e "Next steps:"
  echo -e "  1. Build Docker image: ${YELLOW}npm run dockerbuild:prod${NC}"
  echo -e "  2. Set environment: ${YELLOW}export KUBE_TOKEN='your-token'${NC}"
  echo -e "  3. Deploy Phase 1: ${YELLOW}./scripts/deploy-bolt.sh${NC}"
  echo -e ""
  echo -e "For detailed instructions, see: ${BLUE}DEPLOYMENT.md${NC}"
  exit 0
elif [ $ERRORS -eq 0 ]; then
  echo -e "${YELLOW}⚠ Validation passed with $WARNINGS warning(s)${NC}"
  echo ""
  echo -e "Warnings can usually be ignored, but check the details above."
  echo ""
  exit 0
else
  echo -e "${RED}✗ Validation failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
  echo ""
  echo -e "Please fix the errors above before proceeding with deployment."
  echo ""
  exit 1
fi
