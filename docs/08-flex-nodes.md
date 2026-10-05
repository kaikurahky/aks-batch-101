# 8. Flex Nodes

## Flex Nodes とは

AKS Flex Nodes は、自分で管理する Azure VM、別リージョンの VM、オンプレミスやエッジのベアメタルホストを AKS cluster に接続する機能です。Flex node agent が隔離された Kubernetes node 環境をホスト上に作り、AKS control plane に参加させます。

2026 年 9 月時点で **Public Preview** です。SLA 対象外で本番利用向けではありません。

## 適するバッチ用途

- データ所在地の都合で選択した処理だけ外部拠点で実行
- 既存ラボ機器、Arm64、特殊なベアメタル資源を活用
- AKS リージョン外の既存計算資源を統一 Kubernetes API から操作

単に Azure 内で安価にバッチを増減したい場合は、Cluster Autoscaler、Node Auto Provisioning、Spot node pool を先に検討してください。

## 重要な責任分界

| 対象 | AKS 管理 node pool | Flex Node |
|---|---|---|
| VM の作成・削除 | AKS | 利用者 |
| ホスト OS 更新 | AKS の node image 運用 | 利用者 |
| ホスト容量の増減 | Cluster Autoscaler / NAP | 利用者 |
| Kubernetes scheduling | AKS | AKS |
| Node 上の隔離環境 | AKS | Flex node agent |

**Flex Node は Cluster Autoscaler がホストを増減する仕組みではありません。** 外部ホストの調達、障害対応、パッチ、ネットワークは利用者の責任です。

## 前提条件

- Flex Nodes preview を利用できるサブスクリプション
- 既存 AKS cluster
- Ubuntu 24.04 の amd64 または arm64 ホスト
- AKS API server とホスト間の通信
- Azure Arc managed identity、Azure VM managed identity、または service principal
- Flex node agent
- 複数サイト間を接続する Unbounded-Net
- 公式手順が指定する `aks-preview` extension

プレビューの CLI version と agent は変更され得ます。この教材に固定コピーせず、必ず最新の公式手順を使います。

## Step 1: 公式ワークフローで接続する

次の順番で進めます。

1. [Plan flex nodes deployment](https://learn.microsoft.com/azure/aks/plan-flex-nodes-deployment)
2. [Prepare an AKS cluster](https://learn.microsoft.com/azure/aks/prepare-aks-cluster-for-flex-nodes)
3. [Prepare host and identity](https://learn.microsoft.com/azure/aks/prepare-flex-node-host)
4. [Configure networking and create pool](https://learn.microsoft.com/azure/aks/configure-flex-nodes-networking)
5. [Attach a flex node](https://learn.microsoft.com/azure/aks/attach-flex-node-to-aks)

本教材の AKS cluster を使う場合、公式手順の環境ファイルへ `$RESOURCE_GROUP` と `$AKS_CLUSTER` を設定します。プレビュー操作を始める前に、組織の管理者から許可を得てください。

## Step 2: Node を確認する

```bash
kubectl get nodes \
  -L aks.microsoft.com/compute-type,kubernetes.io/arch,kubernetes.io/os
```

公式ラベルを確認し、Flex Node 名を変数へ入れます。

```bash
export FLEX_NODE="<Flex Node の名前>"
kubectl get node "$FLEX_NODE" --show-labels
```

## Step 3: バッチ専用 label と taint を付ける

```bash
kubectl label node "$FLEX_NODE" workload=flex-batch
kubectl taint node "$FLEX_NODE" workload=flex-batch:NoSchedule
```

label は Flex 用 Job の配置先を限定し、taint は toleration を持たない一般 Pod が Flex Node に配置されるのを防ぎます。プレビュー固有の自動 label ではなく、この教材で付ける `workload=flex-batch` を使うため、実装変更の影響を受けにくい構成です。

## Step 4: Flex Node へ Job を配置する

[`06-flex-job.yaml`](../manifests/06-flex-job.yaml) は、`workload=flex-batch` の nodeSelector と `flex-batch` toleration を持ちます。

```bash
kubectl apply -f rendered/06-flex-job.yaml
kubectl get pods --namespace "$NAMESPACE" --output wide --watch
kubectl logs --namespace "$NAMESPACE" job/flex-job
```

Pod の `NODE` 列が `$FLEX_NODE` なら成功です。

Flex Node を追加し直した場合は、新しい Node にも同じ label と taint を付けます。

## Step 5: 比較する

```bash
kubectl delete job flex-job --namespace "$NAMESPACE" --ignore-not-found
kubectl apply -f rendered/01-manual-job.yaml
```

- `flex-job` は Flex Node だけを選ぶ
- `manual-job` は AKS 管理 `batchpool` だけを選ぶ
- KEDA ScaledJob は現在 `batchpool` を選ぶ

KEDA の Worker を Flex Nodes に送る場合は、ScaledJob の nodeSelector と toleration を Flex 用に変更できます。ただし Queue が増えても Flex ホスト自体は自動追加されないため、最大 Job 数を既存 Flex 容量に合わせて制限します。

## 後片付け

Flex Node は、Job、taint、AKS 側 pool、agent、ホスト、ネットワークの順序を考慮して公式の削除手順で外します。先にリソースグループだけを削除してホスト側 agent を残さないでください。
