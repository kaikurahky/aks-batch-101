# AKS Batch 101

Azure Kubernetes Service (AKS) を初めて使う方向けに、**Kubernetes の基本 → 通常の Web アプリ → バッチ処理 → オートスケール → AKS Flex Nodes** の順で学ぶハンズオン教材です。

## このハンズオンで学ぶこと

1. AKS、Node、Pod、Namespace、Deployment、Service の役割を区別する
2. Web 用の環境を作り、ClusterIP、port-forward、任意の LoadBalancer 公開を試す
3. Web Pod の自己修復、ローリング更新、ロールバック、手動スケールを観察する
4. Azure Container Registry (ACR) でバッチのイメージをビルドする
5. Microsoft Entra Workload ID で Storage Queue にパスワードレス接続する
6. 手動 Job、並列 Job、Indexed Job、CronJob を実行する
7. KEDA `ScaledJob` と Cluster Autoscaler で Job 数と Node 数を別々に増減する
8. Flex Nodes に選択した Job を配置し、適用範囲と運用責任を理解する
9. Job の取消、障害調査、リソース削除を行う

## 構成

| 順序 | 教材 | 内容 |
|---|---|---|
| 1 | [最初におさえるポイント](docs/01-fundamentals.md) | Kubernetes の仕組み、基本リソース、Service と通信経路、Web とバッチの違い |
| 2 | [共通の AKS 環境構築](docs/02-environment-setup.md) | AKS Standard、ACR、Storage Queue、バッチ用ノードプール |
| 3 | [通常の Web アプリ](docs/03-web-app.md) | Web 用 node pool、Deployment、Service、公開、自己修復、更新、スケール |
| 4 | [コンテナーイメージと Workload Identity](docs/04-image-and-identity.md) | バッチの ACR Build、ServiceAccount、パスワードレス認証 |
| 5 | [Job と CronJob](docs/05-jobs-and-cronjobs.md) | 手動、並列、Indexed、定期実行、取消 |
| 6 | [KEDA と Node オートスケール](docs/06-keda-and-node-autoscaling.md) | Queue 駆動、ScaledJob、Cluster Autoscaler |
| 7 | [利用者の実行フロー](docs/07-operator-workflow.md) | 投入、監視、ログ、取消、再実行 |
| 8 | [Flex Nodes](docs/08-flex-nodes.md) | プレビュー準備、外部計算資源への Job 配置、制約 |
| 9 | [問題解決と後片付け](docs/09-troubleshooting-cleanup.md) | Web 接続、Pending、KEDA、Identity、Node、削除 |

初めての方は第 1～3 章で Web の基本操作を学んでからバッチへ進んでください。Web 演習は公開済みイメージを使うため、Worker のビルドや Identity 設定を先に行う必要はありません。

## 学習環境の構成

```text
Web 演習: web-lab
  HTTP クライアント
    -> Service (ClusterIP / 任意の LoadBalancer)
    -> Deployment が維持する Web Pod 2 個
    -> webpool 1 台（演習後に削除）

バッチ演習: batch-lab
  Azure Storage Queue -> KEDA ScaledJob -> Job/Pod 0..N 個
                                            |
                                   リソース不足の Pending
                                            |
                         Cluster Autoscaler -> batchpool 0..N 台

Flex 演習: 選択した Job -> 利用者管理の Flex Node（第 8 章）
  ※ Flex ホストの台数は Cluster Autoscaler の管理外
```

KEDA と Cluster Autoscaler は別物です。KEDA は **Job/Pod 数**、Cluster Autoscaler は **Node 数**を変更します。Flex Node のホスト台数は Cluster Autoscaler の管理対象ではありません。

## 前提条件

- Azure サブスクリプション
- リソースグループ、ロール割り当て、AKS、ACR、Storage を作成できる権限
- Bash、`curl`、`jq`、`sha256sum`
- Azure CLI 2.60 以降
- `kubectl`
- `envsubst`（Ubuntu では `gettext-base` パッケージ）
- Flex Nodes 演習のみ: 対象サブスクリプションでプレビュー利用が許可され、外部 Ubuntu 24.04 ホストを用意できること

ローカル Docker は不要です。Web は公開済み NGINX イメージを使い、バッチのイメージは ACR Tasks でビルドします。Web 演習には Docker Hub への pull 到達性が必要です。

## 最初の準備

```bash
cd /home/hikurais/aks-batch-101
chmod +x scripts/*.sh

az login --use-device-code
az account list --output table
az account set --subscription "<使用するサブスクリプション名または ID>"
./scripts/check-prerequisites.sh

cp scripts/set-env.sh.example scripts/set-env.sh
source scripts/set-env.sh
```

以降は第 1 章から順番に進めてください。

## 費用と注意

- AKS のコントロールプレーンを Free tier にしても、VM、ACR、Storage、Load Balancer、公開 IP などには料金が発生します。
- `systempool` は常時 1 台、`batchpool` は未使用時 0 台になる学習構成です。
- Web 演習中は `webpool` を 1 台追加します。公開演習は任意で、送信元を制限した HTTP テストです。本番用の HTTPS・認証構成ではありません。
- Web の Namespace と node pool は第 3 章の終了時に削除し、共通 AKS をバッチ演習で再利用します。
- Node の起動と縮退には数分かかります。KEDA の Pod スケールより遅いのが正常です。
- Flex Nodes は 2026 年 9 月時点でプレビューです。SLA 対象外であり、本番環境には使わないでください。
- 実習後は必ず[後片付け](docs/09-troubleshooting-cleanup.md)を実施してください。

## 公式資料

- [AKS overview](https://learn.microsoft.com/azure/aks/what-is-aks)
- [Kubernetes Services in AKS](https://learn.microsoft.com/azure/aks/concepts-network-services)
- [Jobs](https://kubernetes.io/docs/concepts/workloads/controllers/job/)
- [AKS scaling overview](https://learn.microsoft.com/azure/aks/concepts-scale)
- [KEDA add-on for AKS](https://learn.microsoft.com/azure/aks/keda-about)
- [Cluster Autoscaler](https://learn.microsoft.com/azure/aks/cluster-autoscaler-overview)
- [Flex Nodes for AKS](https://learn.microsoft.com/azure/aks/flex-nodes-for-aks-overview)
