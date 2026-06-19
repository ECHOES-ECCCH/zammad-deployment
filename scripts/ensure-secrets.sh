#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-staging}"
NAMESPACE="${ZAMMAD_STAGING_NAMESPACE}"

PRODUCT_NAME="${ZAMMAD_PRODUCT_NAME:-Zammad Staging}"
ORGANIZATION="${ZAMMAD_ORGANIZATION:-Example Organization}"
ADMIN_EMAIL="${ZAMMAD_ADMIN_EMAIL:-zammad-admin@example.com}"
ADMIN_FIRSTNAME="${ZAMMAD_ADMIN_FIRSTNAME:-Breakglass}"
ADMIN_LASTNAME="${ZAMMAD_ADMIN_LASTNAME:-Admin}"
LOCALE="${ZAMMAD_LOCALE:-pl-pl}"

POSTGRES_SECRET_NAME="${POSTGRES_SECRET_NAME:-postgresql-pass}"
REDIS_SECRET_NAME="${REDIS_SECRET_NAME:-redis-pass}"
AUTOWIZARD_SECRET_NAME="${AUTOWIZARD_SECRET_NAME:-zammad-autowizard}"

FORCE_SECRET_RECREATE="${FORCE_SECRET_RECREATE:-false}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

random_alnum() {
  local length="${1:-40}"
  # Alphanumeric only: avoids URL-encoding issues in Zammad Helm DB/Redis URLs.
  LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c "${length}"
  echo
}

secret_exists() {
  local name="$1"
  oc -n "${NAMESPACE}" get secret "${name}" >/dev/null 2>&1
}

create_or_skip_secret() {
  local name="$1"

  if secret_exists "${name}" && [[ "${FORCE_SECRET_RECREATE}" != "true" ]]; then
    echo "OK: secret/${name} already exists in ${NAMESPACE}; not rotating."
    return 1
  fi

  if secret_exists "${name}" && [[ "${FORCE_SECRET_RECREATE}" == "true" ]]; then
    echo "WARNING: deleting existing secret/${name} because FORCE_SECRET_RECREATE=true"
    oc -n "${NAMESPACE}" delete secret "${name}"
  fi

  return 0
}

require_cmd oc
require_cmd tr
require_cmd head

echo "==> Ensuring namespace exists: ${NAMESPACE}"
oc get namespace "${NAMESPACE}" >/dev/null 2>&1 || oc new-project "${NAMESPACE}" >/dev/null
oc project "${NAMESPACE}" >/dev/null

echo "==> Creating PostgreSQL secret if missing"
if create_or_skip_secret "${POSTGRES_SECRET_NAME}"; then
  PG_ADMIN_PASSWORD="$(random_alnum 48)"
  PG_APP_PASSWORD="$(random_alnum 48)"
  PG_REPL_PASSWORD="$(random_alnum 48)"

  oc -n "${NAMESPACE}" create secret generic "${POSTGRES_SECRET_NAME}" \
    --from-literal=postgresql-admin-password="${PG_ADMIN_PASSWORD}" \
    --from-literal=postgresql-pass="${PG_APP_PASSWORD}" \
    --from-literal=postgresql-replication-password="${PG_REPL_PASSWORD}" \
    --dry-run=client -o yaml | oc apply -f -

  echo "CREATED: secret/${POSTGRES_SECRET_NAME}"
fi

echo "==> Creating Redis secret if missing"
if create_or_skip_secret "${REDIS_SECRET_NAME}"; then
  REDIS_PASSWORD="$(random_alnum 48)"

  oc -n "${NAMESPACE}" create secret generic "${REDIS_SECRET_NAME}" \
    --from-literal=redis-password="${REDIS_PASSWORD}" \
    --dry-run=client -o yaml | oc apply -f -

  echo "CREATED: secret/${REDIS_SECRET_NAME}"
fi

echo "==> Creating AutoWizard secret if missing"
if create_or_skip_secret "${AUTOWIZARD_SECRET_NAME}"; then
  ADMIN_PASSWORD="$(random_alnum 40)"
  AUTOWIZARD_TOKEN="$(random_alnum 32)"

  TMP_FILE="$(mktemp)"
  cat > "${TMP_FILE}" <<EOF
{
  "Token": "${AUTOWIZARD_TOKEN}",
  "TextModuleLocale": {
    "Locale": "${LOCALE}"
  },
  "Users": [
    {
      "login": "${ADMIN_EMAIL}",
      "firstname": "${ADMIN_FIRSTNAME}",
      "lastname": "${ADMIN_LASTNAME}",
      "email": "${ADMIN_EMAIL}",
      "organization": "${ORGANIZATION}",
      "password": "${ADMIN_PASSWORD}"
    }
  ],
  "Organizations": [
    {
      "name": "${ORGANIZATION}"
    }
  ],
  "Settings": [
    {
      "name": "product_name",
      "value": "${PRODUCT_NAME}"
    },
    {
      "name": "organization",
      "value": "${ORGANIZATION}"
    },
    {
      "name": "system_online_service",
      "value": true
    }
  ]
}
EOF

  oc -n "${NAMESPACE}" create secret generic "${AUTOWIZARD_SECRET_NAME}" \
    --from-file=autowizard="${TMP_FILE}" \
    --dry-run=client -o yaml | oc apply -f -

  rm -f "${TMP_FILE}"

  echo "CREATED: secret/${AUTOWIZARD_SECRET_NAME}"
  echo
  echo "IMPORTANT: AutoWizard admin credentials were generated."
  echo "Read them from the secret and copy them to Vault:"
  echo "  oc -n ${NAMESPACE} get secret ${AUTOWIZARD_SECRET_NAME} -o jsonpath='{.data.autowizard}' | base64 -d"
fi

echo
echo "==> Done. Existing secrets were not rotated."
echo
echo "To inspect generated values for Vault copy:"
echo "  oc -n ${NAMESPACE} get secret ${POSTGRES_SECRET_NAME} -o yaml"
echo "  oc -n ${NAMESPACE} get secret ${REDIS_SECRET_NAME} -o yaml"
echo "  oc -n ${NAMESPACE} get secret ${AUTOWIZARD_SECRET_NAME} -o jsonpath='{.data.autowizard}' | base64 -d"
echo
echo "To intentionally rotate/recreate these secrets:"
echo "  FORCE_SECRET_RECREATE=true $0 ${ENVIRONMENT}"