# 1. 最初におさえるポイント

## 到達目標

- Kubernetes が何を管理し、AKS が何を代行するかを説明できる
- Deployment、Service、Namespace、ConfigMap の役割を区別できる
- Web アプリの通信経路と、バッチ処理との違いを説明できる
- Container Apps Jobs と AKS のリソースを対応付けられる
- Pod のスケールと Node のスケールを区別できる
- AKS Standard を採用する理由を説明できる

## Kubernetes と AKS は何をするものか

コンテナーイメージは「アプリと実行に必要なファイルをまとめたもの」です。イメージを起動するとコンテナーになります。しかし、複数のマシンでアプリを動かすには、配置、障害時の再作成、更新、通信先の管理も必要です。

**Kubernetes** はこれらを管理する仕組みです。「このイメージの Pod を 2 個動かしてほしい」という**望ましい状態**を API に登録すると、現在の状態との差を controller が継続的に埋めます。実行コマンドを一度送るだけの仕組みではありません。

**AKS** は Azure が提供するマネージド Kubernetes です。API server や controller などの control plane を Azure が管理します。利用者はアプリ、権限、ネットワーク、Node 構成、更新方針などを設計します。AKS を使っても、アプリ運用がすべて自動化されるわけではありません。

```text
操作端末
  | az: Azure リソースを作成
  +---- Azure Resource Manager ---- AKS / Node pool / ACR / Storage
  |
  | kubectl: Kubernetes リソースを宣言・確認
  +---- AKS control plane
           | API server: リソースの受付窓口
           | Scheduler: Pod の配置先を決める
           | Controllers: 望ましい状態へ近づける
           v
         Node pool
           +---- Node (VM): kubelet / コンテナーランタイム
           |       +---- Pod ---- コンテナー
           |       +---- Pod ---- コンテナー
           +---- Node (VM) ...
```

`az aks create` は cluster を作ります。`kubectl apply` は、その cluster 内に Deployment や Service などを作ります。**AKS を作るだけでは Web アプリは公開されません。**

## 最初に覚える Kubernetes リソース

ここでの「リソース」は Kubernetes API が管理するオブジェクトです。Azure リソースグループ内のリソースとは別の単位です。

| リソース・用語 | 役割 | この教材での例 |
|---|---|---|
| Namespace | cluster 内の名前・権限・Quota の管理範囲 | `web-lab` と `batch-lab` |
| Pod | 一緒に配置する 1 個以上のコンテナーの単位。IP は作り直すと変わり得る | Web server 1 個、Worker 1 個 |
| Deployment | 常時稼働する Pod の個数と更新を管理 | Web Pod を 2 個維持 |
| ReplicaSet | Deployment の下で指定個数の Pod を維持 | 通常は直接編集しない |
| Service | 入れ替わる Pod 群への安定した IP・DNS 名と通信口 | `web` の 80 番ポート |
| EndpointSlice | Service の接続先 Pod IP と ready 状態などを記録 | Ready な Web Pod の一覧 |
| ConfigMap | 秘密ではない設定や小さなテキストを渡す | Web 演習の HTML |
| Secret | パスワードなどを扱うリソース | Base64 は暗号化ではない。RBAC や Key Vault 連携も必要 |
| Job / CronJob | 完了する処理 / 定期的に Job を作る仕組み | バッチ実行 |
| ServiceAccount / RBAC | Pod の主体と、Kubernetes API でできる操作を定義 | Worker 用 Identity の連携 |
| PersistentVolumeClaim (PVC) | Pod と独立した永続ディスクなどを要求 | DB やファイル保存。今回の Web 演習は不要 |
| StatefulSet | 固定的な名前や永続ストレージとの対応が必要な Pod を管理 | DB など。バックアップは別途必要 |
| DaemonSet | 対象 Node ごとに Pod を配置 | 監視・ネットワーク agent |
| HorizontalPodAutoscaler (HPA) | メトリクスを基に Deployment などの Pod 数を調整 | CPU 負荷で Web Pod を増減する発展構成 |

Namespace を分けるだけではネットワーク隔離になりません。必要に応じて NetworkPolicy と RBAC も設定します。

## Service は「アプリそのもの」ではなく「通信の入口」

一般的な「Web サービス」と Kubernetes の **Service** は意味が異なります。Deployment がアプリを動かし、Service がそのアプリへの接続先を提供します。Service だけを作っても Pod は起動しません。

| Service type | 通信の範囲 | 使いどころ |
|---|---|---|
| `ClusterIP`（既定） | cluster 内の仮想 IP と DNS 名 | 内部 API。手元からは演習用の port-forward でも確認可能 |
| `NodePort` | 到達可能な Node IP の特定ポート | ネットワーク経路・Firewall 設定が別途必要。単体で安全なインターネット公開にはならない |
| `LoadBalancer` | AKS が Azure Load Balancer と連携して入口を構成 | 公開 IP、または設定により内部向け IP を用意 |
| `ExternalName` | 外部の DNS 名への別名（CNAME） | DNS の参照先をまとめる。Pod の起動や通信のプロキシはしない |

Service の `selector` と Pod の `labels` が一致すると、その Pod が接続先候補になります。通常は readiness probe を通過した Pod へ通信します。

```text
クライアント
   |
   | HTTP :80 （公開は任意）
   v
Azure Load Balancer / 公開用 Service
   |
   | selector: app=web
   +---- Ready な Pod A :8080 (label: app=web)
   +---- Ready な Pod B :8080 (label: app=web)

cluster 内のアプリ ---- web.web-lab.svc.cluster.local:80
                             |
                        ClusterIP Service ---- 同じ Pod 群
```

- `port`: Service が受け付けるポート。この例では `80`。
- `targetPort`: Pod のアプリが待ち受けるポート。この例では `8080`。
- `containerPort`: コンテナーのポート情報。書くだけでプロセスが起動したり外部公開されたりはしません。
- Service の名前・IP は Pod が置き換わっても維持されます。ただし Service 自体を削除・再作成すると IP が変わることがあります。
- `kubectl port-forward` は API server 経由で選ばれた Pod に接続する開発用トンネルです。Service の負荷分散や Azure Load Balancer の検証を代替しません。

### Ingress / Gateway API は何が違うか

LoadBalancer は主に TCP/UDP の入口です。HTTP のドメイン名や `/api` などのパスで複数 Service に振り分け、TLS を終端したいときは **Ingress controller** または **Gateway API に対応した controller** を組み合わせます。Ingress や HTTPRoute の定義だけでは処理する controller がないため動きません。

最初の演習では仕組みを増やさないため、ClusterIP と LoadBalancer のみを使います。本番公開時にはサポート中の controller、HTTPS、認証、必要な WAF、DNS を選定します。演習の NGINX はコンテンツを配信する **Web server** であり、Ingress controller ではありません。

## YAML、kubectl と「望ましい状態」

Manifest は YAML で書いたリソース定義です。代表的な項目は次のとおりです。

| 項目 | 意味 |
|---|---|
| `apiVersion` / `kind` | API のバージョンとリソースの種類 |
| `metadata.name` / `namespace` | 名前と所属 Namespace |
| `metadata.labels` | 検索や接続先選択のためのキーと値 |
| `spec` | 自分で宣言する望ましい状態 |
| `status` | controller が報告する現在の状態 |

第 3 章のファイルには、たとえば `replicas: 2` と `selector.matchLabels.app: web` が入っています。Deployment の selector は Pod template の label と一致させます。

| コマンド | 調べること・操作 |
|---|---|
| `kubectl config current-context` | 操作先 cluster を確認 |
| `kubectl apply -f <ファイル>` | Manifest の状態を登録・更新 |
| `kubectl get <種類> -n <Namespace>` | 状態の一覧 |
| `kubectl describe <種類> <名前> -n <Namespace>` | 詳細と Event |
| `kubectl logs <Pod名> -n <Namespace>` | コンテナーの標準出力 |
| `kubectl delete <種類> <名前> -n <Namespace>` | リソースを削除 |

`<...>` は自分の値に置き換える記号です。Web 演習では、置き換え不要の具体的なコマンドを使います。

Deployment 管理下の Pod だけを消しても、別の Pod が作られます。「2 個維持する」という宣言が残っているからです。止める場合は Deployment を削除するか replicas を変更します。

## Web アプリとバッチは何が違うか

| 観点 | Web アプリ | バッチ処理 |
|---|---|---|
| 基本 controller | Deployment | Job / CronJob / KEDA ScaledJob |
| 成功とは | リクエストを継続して処理できること | 指定処理が完了して終了すること |
| 通信口 | Service が通常必要 | Queue を取りに行く Worker なら通常不要 |
| 障害時 | Pod を作り直して台数を維持 | Job の再試行上限に従う |
| 入力 | HTTP リクエスト | 引数、ファイル、Queue メッセージなど |
| Pod 数の調整 | 手動 scale / HPA など | parallelism / KEDA ScaledJob |

Web 演習の CPU `requests: 100m` は 0.1 CPU の要求量です。`requests` は配置判断、`limits` は使用上限に関係します。Pod 数を 2 から 3 にしても、既存 Node に空きがあれば VM は増えません。

readiness probe は「リクエストを受けられるか」、liveness probe は「再起動が必要か」を確認します。起動に時間がかかるアプリには startup probe も検討します。外部依存先の一時障害を理由に全 Pod を再起動させないよう設計します。

## Container Apps Jobs との対応

| Container Apps | AKS / Kubernetes | 補足 |
|---|---|---|
| Environment | AKS cluster | AKS は Kubernetes API と Node 群を提供 |
| App | Deployment + Service | 常時稼働するアプリとその通信口 |
| Job | `Job` / `CronJob` / KEDA `ScaledJob` | 起動方式ごとに別リソース |
| Execution | Job オブジェクト | CronJob と ScaledJob は必要時に Job を作る |
| Replica | Pod | 通常は 1 Pod が 1 コンテナー処理単位 |
| Workload profile | Node pool、Node selector、taint | 配置先と VM SKU を選ぶ |

AKS では管理対象が細かく分かれます。その代わり、スケジューリング、再試行、並列度、Node 構成を詳細に制御できます。

## Job、Pod、Node

- **Job**: 完了すべき処理を宣言します。
- **Pod**: Job が作る実行単位です。コンテナーは Pod 内で動きます。
- **Node**: Pod を実行する VM または Flex Node ホストです。
- **Node pool**: 同じ構成の AKS 管理 Node の集合です。

`completions: 12`、`parallelism: 4` の Job は、全 12 タスクを最大 4 Pod ずつ処理します。4 台の Node を意味しません。

## 3 層のスケール

| 層 | この教材の機能 | 何を増減するか |
|---|---|---|
| タスク | KEDA `ScaledJob` | Queue 長に応じた Job |
| 実行 | Job `parallelism` | 同時 Pod |
| 計算基盤 | Cluster Autoscaler | AKS 管理 Node |

KEDA が Job を増やしても Node に空きがなければ Pod は `Pending` になります。Cluster Autoscaler は、この「リソース不足で配置できない Pod」を見て Node を増やします。

## AKS Standard を使う理由

通常は運用負担の少ない **AKS Automatic** が推奨です。この教材では、次の学習目的から **AKS Standard** を使います。

- バッチ専用 User node pool を 0 台まで縮退させる
- Cluster Autoscaler の最小・最大台数を観察する
- taint / toleration / nodeSelector を学ぶ
- Flex Nodes と AKS 管理 Node の違いを比較する

本番設計では、必要な制御が Automatic で満たせるかを先に検討してください。

## Day-0 の設計

この教材は Azure CNI Overlay と Cilium を使います。Pod IP を VNet から大量消費せず、Network Policy にも対応できる一般的な構成です。ネットワーク方式や Private cluster は後から変えにくいため、本番では作成前に設計します。

学習環境は操作を簡単にするため Public API server を使います。組織環境では Private cluster、API server authorized IP ranges、Firewall などを検討してください。

## 理解度チェック

1. Service だけを作ると Web アプリも起動しますか。
2. Deployment 管理下の Pod を 1 個削除すると、どうなりますか。
3. Web の Pod 数を 2 から 3 にすると Node も 3 台になりますか。
4. KEDA が 20 個の Job を作ったとき、Node も直ちに 20 台になりますか。
5. `parallelism` と `completions` の違いは何ですか。
6. Flex Node のホスト OS を更新する責任は誰にありますか。

答えは順に「起動しない」「必要台数を満たすよう再作成される」「ならない」「ならない」「同時実行数と総完了数」「Flex Node ホストの管理者」です。

次は[環境構築](02-environment-setup.md)へ進みます。

## 公式資料

- [AKS の主要な概念](https://learn.microsoft.com/azure/aks/core-aks-concepts)
- [Kubernetes Services in AKS](https://learn.microsoft.com/azure/aks/concepts-network-services)
- [Kubernetes Deployment](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [Kubernetes ConfigMap](https://kubernetes.io/docs/concepts/configuration/configmap/)
