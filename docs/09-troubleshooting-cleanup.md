# 9. 問題解決と後片付け

## Web アプリに接続できない

Web 演習は `web-lab`、バッチ演習は `$NAMESPACE`（既定 `batch-lab`）です。調査先 Namespace を取り違えないようにします。

```bash
kubectl get deployments,pods,services -n web-lab -o wide
kubectl describe deployment web -n web-lab
kubectl get events -n web-lab --sort-by=.lastTimestamp
kubectl get endpointslices -n web-lab \
  -l kubernetes.io/service-name=web -o yaml
kubectl logs -n web-lab -l app=web --prefix --tail=100
```

| 状態 | 確認すること |
|---|---|
| Pod が Pending | `workload=web` label の Ready Node があるか、CPU / メモリに空きがあるか |
| ImagePullBackOff | 公開 registry への到達性、tag、Docker Hub の pull 制限。必要なら承認済み ACR へ image を取り込んで配置 |
| EndpointSlice の接続先が空 | Service の selector と Pod label が一致しているか |
| Pod が Ready にならない | readiness probe、`http` port の 8080、ConfigMap の参照名 |
| ローカルの 8080 番に接続できない | port-forward の実行端末・プロセス・ポート競合。Pod 更新後はトンネルを再開する |
| Service に EXTERNAL-IP がない | ClusterIP の `<none>` は正常。公開用の `web-public` を作ったか |
| 公開 Service の EXTERNAL-IP が pending | `kubectl describe service web-public -n web-lab` で権限・Policy・quota の Event を確認 |
| 公開 IP はあるが応答しない | `loadBalancerSourceRanges` が実際の送信元 IP か。VPN / NAT / Proxy、HTTP とポート、LB の反映待ちを確認 |
| rollout がタイムアウト | 新 Pod の Pending / probe 失敗 / image pull 失敗を調査。更新には一時的な追加容量が必要 |

port-forward だけ成功する場合は、アプリ自体ではなく Service の selector・通信経路・Load Balancer 側に原因がある可能性があります。公開制限を全面解除して回避しないでください。

## Pod が Pending

```bash
kubectl describe pod --namespace "$NAMESPACE" "<Pod 名>"
kubectl get events --namespace "$NAMESPACE" --sort-by=.lastTimestamp
kubectl get nodes -L agentpool,workload
```

代表例:

- `untolerated taint`: toleration がない
- `didn't match Pod's node affinity/selector`: `workload=batch` Node がまだない
- `Insufficient cpu`: request に対して容量不足
- `Too many pods`: Node の Pod 上限

Cluster Autoscaler が有効か確認:

```bash
az aks nodepool show \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$AKS_CLUSTER" \
  --name "$BATCH_NODEPOOL" \
  --query '{enabled:enableAutoScaling,min:minCount,max:maxCount,count:count}' \
  --output yaml
```

## ImagePullBackOff

```bash
kubectl describe pod --namespace "$NAMESPACE" "<Pod 名>"
az acr repository show-tags \
  --name "$ACR_NAME" \
  --repository "$IMAGE_NAME" \
  --output table
```

image 名、tag、AKS kubelet identity の `AcrPull`、ACR ネットワーク到達性を確認します。

## Workload Identity の認証エラー

```bash
kubectl get serviceaccount \
  --namespace "$NAMESPACE" \
  "$SERVICE_ACCOUNT_NAME" \
  --output yaml

az identity federated-credential list \
  --resource-group "$RESOURCE_GROUP" \
  --identity-name "$WORKLOAD_IDENTITY_NAME" \
  --output table
```

確認点:

- subject が `system:serviceaccount:<namespace>:<serviceaccount>` と完全一致
- Pod template に `azure.workload.identity/use: "true"` label がある
- client ID annotation が正しい
- Role assignment の反映待ちではない

## KEDA が Job を作らない

```bash
kubectl describe scaledjob queue-worker --namespace "$NAMESPACE"
kubectl logs \
  --namespace kube-system \
  --selector app=keda-operator \
  --tail=200
```

Queue 名、Storage account 名、TriggerAuthentication、KEDA operator のエラーを確認します。

## Job が失敗する

```bash
kubectl get pods --namespace "$NAMESPACE" \
  --selector job-name="<Job 名>"
kubectl logs --namespace "$NAMESPACE" "<Pod 名>" --previous
kubectl describe job --namespace "$NAMESPACE" "<Job 名>"
```

`--previous` は同じ Pod 内でコンテナーが再起動した場合に使います。`restartPolicy: Never` では別 Pod になることが多いため、失敗 Pod が削除される前にログを採取します。

## すべての実習 workload を止める

Web 演習を片付けていない場合は、まず port-forward を終了します。次はこの教材で作成した専用 Namespace だけを対象にします。

```bash
kubectl delete namespace web-lab --ignore-not-found --wait=true
```

Web 用 VM の費用も止めるには、[第 3 章の後片付け](03-web-app.md)で `webpool` を削除します。続いてバッチ workload を止めます。

```bash
kubectl delete scaledjob queue-worker --namespace "$NAMESPACE" --ignore-not-found
kubectl delete cronjob scheduled-job --namespace "$NAMESPACE" --ignore-not-found
kubectl delete jobs --namespace "$NAMESPACE" --all
```

これだけでは Azure VM や Storage は削除されません。

## Azure リソースを削除する

Flex Nodes を接続した場合は、先に[第 8 章](08-flex-nodes.md)の公式削除手順で host を切り離します。その後:

```bash
source scripts/set-env.sh
./scripts/cleanup.sh
```

削除完了確認:

```bash
az group exists --name "$RESOURCE_GROUP"
```

`false` になれば完了です。

## 学習後の発展

- Spot node pool と checkpoint 対応 Job
- Kueue による複数利用者の queueing と admission control
- Node Auto Provisioning による SKU 選択
- Managed Prometheus / Grafana
- Container Insights と Log Analytics
- Private AKS、Private Endpoint、固定 Egress
- Azure Policy、Deployment Safeguards、Defender for Containers
