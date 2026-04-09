#!/usr/bin/env bash
# ─── Script de validation locale ──────────────────────────────────────────────
# Lance terraform validate sur tous les environnements.
# Usage : bash tests/validate.sh
# Prérequis : terraform installé, AWS credentials configurées

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

ENVIRONMENTS=("dev" "staging" "prod")
FAILURES=0

echo -e "${YELLOW}=== Terraform Validation ===${NC}"
echo ""

for env in "${ENVIRONMENTS[@]}"; do
  DIR="environments/${env}"
  echo -e "→ Validating ${YELLOW}${env}${NC}..."

  if terraform -chdir="${DIR}" init -backend=false -upgrade -input=false > /dev/null 2>&1; then
    if terraform -chdir="${DIR}" validate > /dev/null 2>&1; then
      echo -e "  ${GREEN}✓ ${env} is valid${NC}"
    else
      echo -e "  ${RED}✗ ${env} validation FAILED${NC}"
      terraform -chdir="${DIR}" validate
      FAILURES=$((FAILURES + 1))
    fi
  else
    echo -e "  ${RED}✗ ${env} init FAILED${NC}"
    FAILURES=$((FAILURES + 1))
  fi
done

echo ""
echo -e "${YELLOW}=== Terraform fmt check ===${NC}"
if terraform fmt -check -recursive . > /dev/null 2>&1; then
  echo -e "${GREEN}✓ All files are properly formatted${NC}"
else
  echo -e "${RED}✗ Formatting issues found. Run: terraform fmt -recursive .${NC}"
  terraform fmt -check -recursive -diff .
  FAILURES=$((FAILURES + 1))
fi

echo ""
if [ "${FAILURES}" -eq 0 ]; then
  echo -e "${GREEN}=== All checks passed! ===${NC}"
  exit 0
else
  echo -e "${RED}=== ${FAILURES} check(s) failed ===${NC}"
  exit 1
fi
