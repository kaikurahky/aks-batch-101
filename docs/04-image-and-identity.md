# 4. コンテナーイメージと Workload Identity

[Web アプリ演習](03-web-app.md)では、Deployment が Pod を起動し続け、Service が HTTP の入口を提供しました。ここからは処理が完了すると終了する Worker を作ります。Queue へ接続しに行くバッチなので、Web 用の Service や公開 IP は不要です。

Web 演習の Namespace と node pool は片付け、共通の AKS、ACR、Storage は残した状態で進めます。

## Step 1: Worker の動作を理解する

[`worker.py`](../src/batch-worker/worker.py) は `RUN_MODE` で動作を変えます。

| 値 | 動作 |
|---|---|
| `compute` | 指定秒数の計算を模擬し、SHA-256 結果を標準出力へ書く |
| `seed` | Storage Queue に複数メッセージを投入する |
| `queue` | Queue から 1 件取得し、正常終了後に削除する |

Queue メッセージは処理成功後に削除します。処理中に Pod が失敗すると visibility timeout 後に再配信されるため、実処理は同じ `task_id` が複数回届いても安全な冪等設計にします。

## Step 2: ACR 上でビルドする

```bash
source scripts/set-env.sh
./scripts/build-image.sh

az acr repository show-tags \
  --name "$ACR_NAME" \
  --repository "$IMAGE_NAME" \
  --output table
```

AKS の kubelet identity には ACR Pull 権限が設定済みです。Kubernetes Secret に ACR パスワードを保存しません。

## Step 3: Workload Identity を設定する

スクリプトは User Assigned Managed Identity、Storage Queue Data Contributor、Federated credential を作成します。

```bash
./scripts/configure-workload-identity.sh
```

最後に表示された `export` を実行します。

```bash
export WORKLOAD_CLIENT_ID="<表示された client ID>"
./scripts/render-manifests.sh
kubectl apply -f rendered/00-identity.yaml
```

client ID は秘密情報ではありません。パスワードや Storage key を Manifest に保存しないことが重要です。

## Step 4: Manifest を確認する

```bash
kubectl get serviceaccount \
  --namespace "$NAMESPACE" \
  "$SERVICE_ACCOUNT_NAME" \
  --output yaml

grep -R '\${' rendered/ && echo "未置換の変数があります" || true
```

`azure.workload.identity/client-id` annotation があり、未置換の `${...}` がないことを確認します。

## Step 5: 手動 Job を実行する

```bash
kubectl apply -f rendered/01-manual-job.yaml
kubectl get pods --namespace "$NAMESPACE" --watch
kubectl logs --namespace "$NAMESPACE" job/manual-job
```

ログは JSON です。`task_started` と `task_completed` があれば成功です。

## Identity の役割分担

| Identity | 用途 |
|---|---|
| AKS control plane identity | Azure 上の AKS リソース操作 |
| kubelet identity | ACR から image pull |
| batch-worker managed identity | Pod と KEDA から Storage Queue へアクセス |
| ServiceAccount | Kubernetes 内の workload identity の主体 |

1 つの強い Identity を共有せず、用途ごとに分離します。
