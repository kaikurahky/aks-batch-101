# 5. Job と CronJob

[第 4 章](04-image-and-identity.md)で作成したイメージと Identity を使って、Kubernetes の Job を実行します。Web の Deployment は稼働台数を維持しますが、Job は必要な処理の完了を目指します。

## 手動 Job

[`01-manual-job.yaml`](../manifests/01-manual-job.yaml) は 1 回だけ処理します。

- `restartPolicy: Never`: 失敗したコンテナーを同じ Pod 内で再起動しない
- `backoffLimit: 2`: Job controller が失敗を 2 回まで再試行
- `ttlSecondsAfterFinished`: 完了 Job を一定時間後に削除
- `resources.requests`: Scheduler と Cluster Autoscaler が使う必要量

実行:

```bash
kubectl apply -f rendered/01-manual-job.yaml
kubectl get pods --namespace "$NAMESPACE" --watch
```

`batchpool` が 0 台のため、最初の Pod は `Pending` になります。その後 Cluster Autoscaler が Node を追加し、Pod が Running になります。

```bash
kubectl logs --namespace "$NAMESPACE" job/manual-job
kubectl get job --namespace "$NAMESPACE" manual-job
```

同名 Job は完了後も再実行されません。再実行するには削除して作り直します。

```bash
kubectl delete job --namespace "$NAMESPACE" manual-job --ignore-not-found
kubectl apply -f rendered/01-manual-job.yaml
```

## Indexed Job

[`02-indexed-job.yaml`](../manifests/02-indexed-job.yaml) は 12 個の index を最大 4 Pod で処理します。

```bash
kubectl apply -f rendered/02-indexed-job.yaml
kubectl get jobs,pods --namespace "$NAMESPACE" --watch
```

各 Pod には `JOB_COMPLETION_INDEX` が渡されます。Worker はこれをタスク ID に使います。

```bash
kubectl logs --namespace "$NAMESPACE" \
  --selector job-name=indexed-job \
  --prefix
```

`backoffLimitPerIndex` により、失敗 index だけを再試行できます。独立したファイル変換やシミュレーションのパラメータ分割に適します。

## CronJob

[`03-cronjob.yaml`](../manifests/03-cronjob.yaml) は 10 分ごとに Job を作ります。

```bash
kubectl apply -f rendered/03-cronjob.yaml
kubectl get cronjob --namespace "$NAMESPACE"
```

待たずに動作確認する場合:

```bash
kubectl create job \
  --namespace "$NAMESPACE" \
  --from=cronjob/scheduled-job \
  scheduled-job-manual
```

`concurrencyPolicy: Forbid` は前回 Job が動作中なら次回をスキップします。重複実行できない処理に有効です。

停止:

```bash
kubectl patch cronjob scheduled-job \
  --namespace "$NAMESPACE" \
  --type merge \
  --patch '{"spec":{"suspend":true}}'
```

CronJob の suspend は新規 Job 作成を止めます。すでに作成済みの Job は止まりません。

## 実行中 Job の取消

```bash
kubectl delete job --namespace "$NAMESPACE" indexed-job
```

Job と、その Job が管理する Pod が削除されます。外部ストレージへ途中結果を書いている場合、その結果は自動削除されません。業務処理側で冪等性、チェックポイント、再開方法を設計します。
