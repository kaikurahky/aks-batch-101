# 2. 共通の AKS 環境構築

この章では、Web とバッチの両演習で使う cluster を 1 つ作ります。次の[第 3 章](03-web-app.md)で Web 用 node pool、Deployment、Service を追加し、Web アプリを先に動かします。

ACR と Storage Queue、KEDA、Workload Identity はバッチに向けて先に用意しますが、通常の Web アプリを動かすために Queue や KEDA が必須という意味ではありません。

## 作成するもの

- ACR Basic
- Storage Account と Queue
- AKS Standard (Free tier)
- `systempool`: 1 台
- `batchpool`: 0～5 台、Cluster Autoscaler 有効

`systempool` は Kubernetes のシステムコンポーネント用です。バッチ Pod は taint 付き `batchpool` にだけ配置します。

Web 用の `webpool` はまだ作りません。第 3 章で 1 台追加し、Web 演習の終了時に削除します。Web の稼働により `batchpool` の 0 台への縮退が妨げられないよう、配置先を分けます。

## Step 1: 変数を確認する

```bash
source scripts/set-env.sh
printf '%s\n' "$RESOURCE_GROUP" "$AKS_CLUSTER" "$ACR_NAME" "$STORAGE_ACCOUNT"
```

VM SKU がリージョンで利用できない場合は `SYSTEM_NODE_VM_SIZE` と `BATCH_NODE_VM_SIZE` を変更します。B-series は CPU クレジットにより性能が変動するため、この教材では使いません。

## Step 2: Azure リソースを作る

```bash
./scripts/create-environment.sh
```

作成には 10～20 分程度かかります。スクリプトは `set -euo pipefail` を使い、途中の失敗を成功扱いしません。

## Step 3: Node pool を確認する

```bash
az aks nodepool list \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$AKS_CLUSTER" \
  --query '[].{name:name,mode:mode,count:count,min:minCount,max:maxCount,autoscale:enableAutoScaling}' \
  --output table

kubectl get nodes -L agentpool,workload
```

最初は `systempool` の Node だけが見えます。`batchpool` は 0 台なので正常です。

## Step 4: KEDA と Workload Identity を確認する

```bash
az aks show \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER" \
  --query '{oidc:oidcIssuerProfile.enabled,workloadIdentity:securityProfile.workloadIdentity.enabled,keda:workloadAutoScalerProfile.keda.enabled}' \
  --output yaml

kubectl get pods --namespace kube-system | grep keda
```

3 項目が `true` で、KEDA operator と metrics API server が Running なら準備完了です。

ここではまだ Deployment も Service もないため、アプリ用 URL はありません。AKS API server の FQDN は `kubectl` の管理接続先であり、Web アプリの URL とは別です。

次は[通常の Web アプリを AKS で動かす](03-web-app.md)へ進みます。バッチ Worker のビルドや Job 実行は Web 演習の後です。

## この構成で省略した本番要素

- Private AKS cluster
- Azure Firewall または固定 Egress
- Private Endpoint を使う ACR / Storage
- Managed Prometheus、Container Insights、Grafana
- 可用性ゾーンに分散した複数 system Node
- Azure Policy、Defender for Containers
- Maintenance window と自動アップグレード

これらは Job の基本動作を理解した後に追加してください。特にネットワーク方式と API server 公開範囲は Day-0 の設計事項です。
