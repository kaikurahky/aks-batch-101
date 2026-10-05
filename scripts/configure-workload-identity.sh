#!/usr/bin/env bash

set -euo pipefail

: "${RESOURCE_GROUP:?source scripts/set-env.sh first}"
: "${LOCATION:?}"
: "${AKS_CLUSTER:?}"
: "${STORAGE_ACCOUNT:?}"
: "${WORKLOAD_IDENTITY_NAME:?}"
: "${NAMESPACE:?}"
: "${SERVICE_ACCOUNT_NAME:?}"

identity_json=$(az identity create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$WORKLOAD_IDENTITY_NAME" \
  --location "$LOCATION" \
  --output json)

export WORKLOAD_CLIENT_ID
WORKLOAD_CLIENT_ID=$(jq -r '.clientId' <<<"$identity_json")
principal_id=$(jq -r '.principalId' <<<"$identity_json")
storage_id=$(az storage account show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$STORAGE_ACCOUNT" \
  --query id --output tsv)

az role assignment create \
  --assignee-object-id "$principal_id" \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Queue Data Contributor" \
  --scope "$storage_id" \
  --output table

oidc_issuer=$(az aks show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER" \
  --query oidcIssuerProfile.issuerUrl \
  --output tsv)

az identity federated-credential create \
  --resource-group "$RESOURCE_GROUP" \
  --identity-name "$WORKLOAD_IDENTITY_NAME" \
  --name "${SERVICE_ACCOUNT_NAME}-federated" \
  --issuer "$oidc_issuer" \
  --subject "system:serviceaccount:${NAMESPACE}:${SERVICE_ACCOUNT_NAME}" \
  --audience api://AzureADTokenExchange \
  --output table

printf '\n次の値を現在のシェルに設定してください:\n'
printf 'export WORKLOAD_CLIENT_ID=%q\n' "$WORKLOAD_CLIENT_ID"

