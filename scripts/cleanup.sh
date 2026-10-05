#!/usr/bin/env bash

set -euo pipefail

: "${RESOURCE_GROUP:?source scripts/set-env.sh first}"

printf 'Deleting resource group %s...\n' "$RESOURCE_GROUP"
az group delete --name "$RESOURCE_GROUP" --yes
printf '削除要求を受け付けました。完了状況は az group exists --name %q で確認できます。\n' "$RESOURCE_GROUP"

