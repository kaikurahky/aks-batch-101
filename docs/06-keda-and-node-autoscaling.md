# 6. KEDA と Node オートスケール

[Web 演習](03-web-app.md)では Deployment の Pod 数を手動で変更しました。この章では Queue 駆動の Job 数と、それを載せる Node 数を別々の仕組みで自動調整します。

## この章で観察する流れ

1. Seeder が Queue に 20 件投入
2. KEDA が Queue 長を検出
3. KEDA が最大 20 個の Job を作成
4. 配置先がなく Pod が Pending
5. Cluster Autoscaler が `batchpool` を増やす
6. Worker が 1 件ずつ処理して Queue を空にする
7. Job が 0 個に戻り、しばらく後に `batchpool` も 0 台へ戻る

## Step 1: ScaledJob を作る

```bash
kubectl apply -f rendered/05-keda-scaledjob.yaml
kubectl get scaledjob,triggerauthentication --namespace "$NAMESPACE"
```

KEDA は Worker の Managed Identity を使って Queue 長を読みます。接続文字列は使いません。

## Step 2: 監視を始める

別のターミナルで:

```bash
watch -n 5 "kubectl get jobs,pods -n $NAMESPACE -o wide"
```

さらに別のターミナルで:

```bash
watch -n 10 "kubectl get nodes -L agentpool,workload"
```

Cluster Autoscaler の状態:

```bash
kubectl get configmap \
  --namespace kube-system \
  cluster-autoscaler-status \
  --output yaml
```

## Step 3: Queue に 20 件投入する

同名 Seeder を以前実行している場合は削除します。

```bash
kubectl delete job queue-seeder --namespace "$NAMESPACE" --ignore-not-found
kubectl apply -f rendered/04-queue-seeder.yaml
kubectl logs --namespace "$NAMESPACE" job/queue-seeder --follow
```

最初の Seeder は systempool 上で動きます。Queue Worker だけが `batchpool` を要求します。

## Step 4: スケールを説明する

`queueLength: "1"` は 1 Worker あたり 1 メッセージを目標にします。ただし次の理由で常に 20 Worker 同時になるとは限りません。

- KEDA の polling 間隔
- Azure VM の割り当てと Node 起動時間
- VM quota とリージョン在庫
- Worker が先にメッセージを処理する
- `maxReplicaCount`
- Pod の CPU / memory request

KEDA は Node の起動を待たず Job を作れます。`Pending` は直ちに異常とは限りません。

## Step 5: ログと完了を確認する

```bash
kubectl logs \
  --namespace "$NAMESPACE" \
  --selector app=queue-worker \
  --prefix \
  --tail=200

kubectl get jobs --namespace "$NAMESPACE"
kubectl get scaledjob --namespace "$NAMESPACE"
```

Queue が空になると KEDA は新しい Job を作りません。完了 Job は履歴上限と TTL に従って削除されます。

## Step 6: Node が 0 台へ戻るのを確認する

```bash
az aks nodepool show \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$AKS_CLUSTER" \
  --name "$BATCH_NODEPOOL" \
  --query '{count:count,min:minCount,max:maxCount,autoscale:enableAutoScaling}' \
  --output table
```

既定では不要判定や追加後の待機があるため、縮退はすぐには始まりません。学習環境であっても過度に攻撃的な autoscaler profile は、再起動増加や thrashing の原因になります。

## ScaledJob を止める

新規 Job 作成を止めるには:

```bash
kubectl delete scaledjob queue-worker --namespace "$NAMESPACE"
```

すでに作成された Job も止める場合:

```bash
kubectl delete jobs \
  --namespace "$NAMESPACE" \
  --selector scaledjob.keda.sh/name=queue-worker
```

Queue メッセージは残るため、ScaledJob を再作成すると再開できます。

## 発展: Cluster Autoscaler、NAP、Flex Nodes

| 選択肢 | 特徴 |
|---|---|
| Cluster Autoscaler | 指定した node pool の台数を変更 |
| Node Auto Provisioning | Pending Pod に合わせて VM SKU と Node を選択 |
| Flex Nodes | 自分で管理する外部ホストを AKS に接続 |

この教材は node pool の挙動を見やすくするため Cluster Autoscaler を使います。多様な SKU を動的に選ぶ場合は NAP を検討します。
