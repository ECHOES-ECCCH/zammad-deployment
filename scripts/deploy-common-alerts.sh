#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-staging}"

case "$ENVIRONMENT" in
  staging)
    NAMESPACE="echoes-helpdesk-staging"
    ;;
  production)
    NAMESPACE="echoes-helpdesk-production"
    ;;
  *)
    echo "Unknown environment: $ENVIRONMENT"
    exit 1
    ;;
esac

helm upgrade --install "zammad-common-alerts" \
  oci://registry.paas.psnc.pl/helm/common-alerts \
  -n "$NAMESPACE" \
  -f "environments/${ENVIRONMENT}/common-alerts-values.yaml"