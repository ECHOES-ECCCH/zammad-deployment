#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-staging}"

case "${ENVIRONMENT}" in
  staging)
    NAMESPACE="${ZAMMAD_STAGING_NAMESPACE:-echoes-helpdesk-staging}"
    ROUTE_NAME="${ZAMMAD_ROUTE_NAME:-zammad}"
    ;;
  *)
    echo "ERROR: unknown environment: ${ENVIRONMENT}" >&2
    exit 1
    ;;
esac

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_cmd oc
require_cmd curl

echo "==> Smoke test for ${ENVIRONMENT}"
echo "Namespace: ${NAMESPACE}"
echo

echo "==> Checking namespace"
oc get namespace "${NAMESPACE}" >/dev/null

echo "==> Checking Helm release"
helm status zammad -n "${NAMESPACE}" >/dev/null

echo "==> Checking pods"
oc -n "${NAMESPACE}" get pods

FAILED_PODS="$(oc -n "${NAMESPACE}" get pods --no-headers | awk '$3 ~ /CrashLoopBackOff|Error|ImagePullBackOff|ErrImagePull|CreateContainerConfigError|CreateContainerError|OOMKilled/ {print}' || true)"
if [[ -n "${FAILED_PODS}" ]]; then
  echo
  echo "ERROR: Some pods are failing:"
  echo "${FAILED_PODS}"
  exit 1
fi

echo
echo "==> Checking deployments rollout"

for DEPLOY in zammad-nginx zammad-railsserver zammad-scheduler zammad-websocket; do
  if oc -n "${NAMESPACE}" get deploy "${DEPLOY}" >/dev/null 2>&1; then
    oc -n "${NAMESPACE}" rollout status "deploy/${DEPLOY}" --timeout=180s
  else
    echo "WARNING: deploy/${DEPLOY} not found; skipping"
  fi
done

echo
echo "==> Checking statefulsets rollout"

for STS in zammad-postgresql zammad-redis zammad-elasticsearch-master; do
  if oc -n "${NAMESPACE}" get statefulset "${STS}" >/dev/null 2>&1; then
    oc -n "${NAMESPACE}" rollout status "statefulset/${STS}" --timeout=300s
  else
    echo "WARNING: statefulset/${STS} not found; skipping"
  fi
done

echo
echo "==> Checking route"

ROUTE_HOST="$(oc -n "${NAMESPACE}" get route "${ROUTE_NAME}" -o jsonpath='{.spec.host}')"

if [[ -z "${ROUTE_HOST}" ]]; then
  echo "ERROR: route/${ROUTE_NAME} has no host" >&2
  exit 1
fi

BASE_URL="https://${ROUTE_HOST}"
echo "URL: ${BASE_URL}"

HTTP_CODE="$(curl -k -sS -o /dev/null -w '%{http_code}' "${BASE_URL}/")"

case "${HTTP_CODE}" in
  200|301|302)
    echo "OK: HTTP endpoint returned ${HTTP_CODE}"
    ;;
  *)
    echo "ERROR: HTTP endpoint returned ${HTTP_CODE}" >&2
    exit 1
    ;;
esac

if [[ -n "${ZAMMAD_MONITORING_TOKEN:-}" ]]; then
  echo
  echo "==> Checking Zammad monitoring health endpoint"

  HEALTH_URL="${BASE_URL}/api/v1/monitoring/health_check?token=${ZAMMAD_MONITORING_TOKEN}"
  HEALTH_JSON="$(curl -k -fsS "${HEALTH_URL}")"
  echo "${HEALTH_JSON}"

  if command -v jq >/dev/null 2>&1; then
    HEALTHY="$(echo "${HEALTH_JSON}" | jq -r '.healthy // false')"
    MESSAGE="$(echo "${HEALTH_JSON}" | jq -r '.message // ""')"

    if [[ "${HEALTHY}" != "true" ]]; then
      echo "ERROR: health check is not healthy: ${MESSAGE}" >&2
      exit 1
    fi

    echo "OK: health check healthy=true"
  else
    echo "WARNING: jq not installed; printed health JSON but did not assert .healthy"
  fi
else
  echo
  echo "WARNING: ZAMMAD_MONITORING_TOKEN not set; skipping health endpoint check."
  echo "After UI setup, get token from Admin -> System -> Monitoring and run:"
  echo "  export ZAMMAD_MONITORING_TOKEN='...'"
fi

echo
echo "==> Checking recent warning/error events"
oc -n "${NAMESPACE}" get events --sort-by=.lastTimestamp | tail -30

echo
echo "OK: smoke test completed"
EOF
