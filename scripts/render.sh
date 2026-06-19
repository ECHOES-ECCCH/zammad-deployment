#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-staging}"
CHART_VERSION="${ZAMMAD_CHART_VERSION:-16.2.2}"
OUT_DIR="rendered"
OUT_FILE="${OUT_DIR}/${ENVIRONMENT}.yaml"

mkdir -p "${OUT_DIR}"

helm repo add zammad https://zammad.github.io/zammad-helm --force-update >/dev/null
helm repo update >/dev/null

helm template zammad zammad/zammad \
  --version "${CHART_VERSION}" \
  -f "environments/${ENVIRONMENT}/values.yaml" \
  -f "environments/${ENVIRONMENT}/values-openshift.yaml" \
  -f "environments/${ENVIRONMENT}/values-images.yaml" \
  > "${OUT_FILE}"

echo "Rendered to ${OUT_FILE}"
echo
echo "Images found:"
grep -n 'image:' "${OUT_FILE}" | sort -u || true
