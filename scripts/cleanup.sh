#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-staging}"
NAMESPACE="${ZAMMAD_STAGING_NAMESPACE}"

helm uninstall zammad -n "${NAMESPACE}" --no-hooks || true

echo
echo "Remaining objects:"
oc -n "${NAMESPACE}" get all || true

echo
echo "PVCs left in ${NAMESPACE}:"
oc -n "${NAMESPACE}" get pvc || true

echo
echo "For a full test reset, run manually:"
echo "  oc delete project ${NAMESPACE}"
