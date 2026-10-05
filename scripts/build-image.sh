#!/usr/bin/env bash

set -euo pipefail

: "${ACR_NAME:?source scripts/set-env.sh first}"
: "${IMAGE_NAME:?}"
: "${IMAGE_TAG:?}"

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
az acr build \
  --registry "$ACR_NAME" \
  --image "${IMAGE_NAME}:${IMAGE_TAG}" \
  "$repo_root/src/batch-worker"

printf 'Built image: %s.azurecr.io/%s:%s\n' "$ACR_NAME" "$IMAGE_NAME" "$IMAGE_TAG"

