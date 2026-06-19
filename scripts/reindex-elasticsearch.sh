#!/usr/bin/env bash
set -euo pipefail

ENVIRONMENT="${1:-staging}"
NAMESPACE="${ZAMMAD_STAGING_NAMESPACE}"
JOB_NAME="zammad-reindex-manual-$(date +%Y%m%d%H%M%S)"

# Upstream chart creates a suspended cronjob template for reindex.
# This creates a one-off job from that template.
oc -n "${NAMESPACE}" create job "${JOB_NAME}" --from=cronjob/zammad-cronjob-reindex
oc -n "${NAMESPACE}" logs -f "job/${JOB_NAME}" --all-containers=true
