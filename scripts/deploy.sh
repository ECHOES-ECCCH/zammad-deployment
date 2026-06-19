#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-staging}"
CHART_VERSION="${ZAMMAD_CHART_VERSION:-16.2.2}"
HELM_TIMEOUT="${HELM_TIMEOUT:-45m}"
NAMESPACE="${ZAMMAD_STAGING_NAMESPACE:-echoes-helpdesk-staging}"


helm repo add zammad https://zammad.github.io/zammad-helm --force-update >/dev/null
helm repo update >/dev/null

helm upgrade --install zammad zammad/zammad \
  --version "${CHART_VERSION}" \
    -n "${NAMESPACE}" \
  -f "environments/${ENVIRONMENT}/values.yaml" \
  -f "environments/${ENVIRONMENT}/values-openshift.yaml" \
  -f "environments/${ENVIRONMENT}/values-images.yaml" \
  -f "environments/${ENVIRONMENT}/values-monitoring.yaml" \
  --wait \
  --timeout "${HELM_TIMEOUT}"

if [[ -f "environments/${ENVIRONMENT}/route.yaml" ]]; then
  oc apply -f "environments/${ENVIRONMENT}/route.yaml"
fi

echo
echo "Deployment requested. Current pods:"
oc -n "${NAMESPACE}" get pods
