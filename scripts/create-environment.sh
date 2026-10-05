#!/usr/bin/env bash

set -euo pipefail

: "${RESOURCE_GROUP:?source scripts/set-env.sh first}"
: "${LOCATION:?}"
: "${ACR_NAME:?}"
: "${STORAGE_ACCOUNT:?}"
: "${QUEUE_NAME:?}"
: "${AKS_CLUSTER:?}"
: "${SYSTEM_NODE_VM_SIZE:?}"
: "${BATCH_NODE_VM_SIZE:?}"
: "${BATCH_NODEPOOL:?}"

az group create --name "$RESOURCE_GROUP" --location "$LOCATION" --output table

az acr create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$ACR_NAME" \
  --sku Basic \
  --output table

az storage account create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$STORAGE_ACCOUNT" \
  --location "$LOCATION" \
  --sku Standard_LRS \
  --kind StorageV2 \
  --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --output table

storage_key=$(az storage account keys list \
  --resource-group "$RESOURCE_GROUP" \
  --account-name "$STORAGE_ACCOUNT" \
  --query '[0].value' --output tsv)

az storage queue create \
  --name "$QUEUE_NAME" \
  --account-name "$STORAGE_ACCOUNT" \
  --account-key "$storage_key" \
  --output table
unset storage_key

az aks create \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER" \
  --location "$LOCATION" \
  --tier free \
  --nodepool-name systempool \
  --node-count 1 \
  --node-vm-size "$SYSTEM_NODE_VM_SIZE" \
  --network-plugin azure \
  --network-plugin-mode overlay \
  --network-dataplane cilium \
  --enable-oidc-issuer \
  --enable-workload-identity \
  --enable-keda \
  --attach-acr "$ACR_NAME" \
  --generate-ssh-keys \
  --output table

az aks nodepool add \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$AKS_CLUSTER" \
  --name "$BATCH_NODEPOOL" \
  --mode User \
  --node-count 0 \
  --node-vm-size "$BATCH_NODE_VM_SIZE" \
  --enable-cluster-autoscaler \
  --min-count 0 \
  --max-count 5 \
  --labels workload=batch \
  --node-taints workload=batch:NoSchedule \
  --output table

az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER" \
  --overwrite-existing

kubectl get nodes -L agentpool,workload

