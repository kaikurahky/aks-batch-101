#!/usr/bin/env bash

set -euo pipefail

: "${IMAGE:?source scripts/set-env.sh first}"
: "${NAMESPACE:?}"
: "${SERVICE_ACCOUNT_NAME:?}"
: "${WORKLOAD_CLIENT_ID:?run configure-workload-identity.sh first}"
: "${STORAGE_ACCOUNT:?}"
: "${QUEUE_NAME:?}"

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
mkdir -p "$repo_root/rendered"

for template in "$repo_root"/manifests/*.yaml; do
  output="$repo_root/rendered/$(basename "$template")"
  envsubst <"$template" >"$output"
  printf 'Rendered %s\n' "$output"
done

