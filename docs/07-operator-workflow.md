# 7. 利用者の実行フロー

## 管理者と利用者を分ける

| 操作 | 管理者 | Job 利用者 |
|---|---:|---:|
| AKS / node pool 作成 | ✓ | |
| ACR / Identity / RBAC 設定 | ✓ | |
| Namespace、ResourceQuota、Policy 設定 | ✓ | |
| 承認済み Job の投入 | | ✓ |
| 自分の Job の確認・取消 | | ✓ |
| cluster-wide Node 操作 | ✓ | |

共有環境で利用者へ `cluster-admin` や Azure Contributor を渡さないでください。Namespace 内の Job、Pod、logs に限定した Kubernetes RBAC を作ります。

## 単発 Job の投入

固定名では同時投入できないため、既存テンプレートから一意な Job 名を作ります。

```bash
run_id=$(date -u +%Y%m%d%H%M%S)
kubectl create job \
  --namespace "$NAMESPACE" \
  --from=cronjob/scheduled-job \
  "batch-${run_id}"
```

入力値を任意に変更できる受付 API は、この教材には含めません。信頼できない入力を Manifest や shell へ直接埋め込まないでください。

## 状態確認

```bash
kubectl get jobs,pods --namespace "$NAMESPACE"
kubectl describe job --namespace "$NAMESPACE" "batch-${run_id}"
kubectl logs --namespace "$NAMESPACE" "job/batch-${run_id}" --follow
```

Job の主要状態:

- `Complete`: 必要数が正常終了
- `Failed`: 再試行上限を超過
- Active > 0: 実行中
- Pod `Pending`: Scheduler が配置先を探している

## 取消

```bash
kubectl delete job --namespace "$NAMESPACE" "batch-${run_id}"
```

Kubernetes API の削除成功は、業務上のロールバック成功を意味しません。外部出力や課金処理がある場合、処理側に取消・補償設計が必要です。

## 再実行

同じ業務キーで再実行するときは、出力先を業務キーで固定し、上書きまたは存在確認を行うと重複結果を抑制できます。Queue は at-least-once 配信として扱い、同じメッセージの複数回処理を前提にします。

## ResourceQuota の例

利用者ごとの暴走を防ぐ場合、管理者が Namespace に次のような上限を設定します。

```yaml
apiVersion: v1
kind: ResourceQuota
metadata:
  name: batch-quota
  namespace: batch-lab
spec:
  hard:
    requests.cpu: "20"
    requests.memory: 20Gi
    count/jobs.batch: "100"
    pods: "50"
```

KEDA の `maxReplicaCount`、ResourceQuota、node pool の `max-count` は別の上限です。3 層すべてを設計します。
