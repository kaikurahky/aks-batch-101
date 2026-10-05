# 3. 通常の Web アプリを AKS で動かす

## 到達目標と前提

[第 2 章](02-environment-setup.md)で作った AKS を使い、まず「HTTP を待ち受け続けるアプリ」の運用を体験します。所要時間の目安は 30～45 分です。

- Web 用 Node pool と Namespace を作る
- Deployment と Service の関係を確認する
- 内部接続、任意の外部公開、ログ、自己修復、更新・ロールバック、手動スケールを試す
- Web とバッチで controller を使い分ける理由を理解する

Worker のビルド、Storage Queue、Workload Identity の設定は **この章では不要**です。公開済みの非 root NGINX イメージを使い、HTML を ConfigMap から読み込みます。静的 Web アプリなので DB や PVC も不要です。本番アプリではソースから image を作って registry に保存します。

コマンドはリポジトリのルートで実行します。`--watch` は状態を表示し続けるため、確認できたら **Ctrl+C** で終了して次へ進んでください。

## この章の構成

```text
AKS
  systempool     システム用
  webpool        Web 用 User pool（この章で 1 台追加）
    Pod A ─┐
    Pod B ─┴─ Deployment/web が 2 個を維持
               ^
               | selector: app=web
               |
    Service/web (ClusterIP)       cluster 内向け
    Service/web-public           任意。Azure Load Balancer 経由の HTTP 公開

  batchpool      バッチ用（まだ 0 台）
```

教材の `webpool` は **1 台固定**です。Pod が 2 個でも Node 障害には耐えられません。本番では複数 Node・可用性ゾーン、分散配置、PDB、監視などが必要です。Web 用 Node は削除するまで課金されます。

## Step 1: 操作先を確認し Web 用 Node pool を作る

```bash
source scripts/set-env.sh
az account show --query '{subscription:name}' --output table
az aks get-credentials \
  --resource-group "$RESOURCE_GROUP" \
  --name "$AKS_CLUSTER"
kubectl config current-context
kubectl cluster-info
```

この教材用 cluster を指していることを確認します。既存 kubeconfig との競合が出た場合は、対象を確認してから認証情報を取得し直してください。

```bash
az aks nodepool add \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$AKS_CLUSTER" \
  --name webpool \
  --mode User \
  --node-count 1 \
  --node-vm-size "$SYSTEM_NODE_VM_SIZE" \
  --labels workload=web \
  --output table

kubectl wait node --selector workload=web \
  --for=condition=Ready --timeout=600s
kubectl get nodes -L agentpool,workload
```

`webpool` の Node が `Ready` なら成功です。再受講で `webpool` が残っている場合は、追加コマンドを再実行せず、その pool の label と状態を確認します。

Deployment の `nodeSelector: {workload: web}` が Web Pod をこの pool に限定します。Node の選択に使う label と、Service が Pod を選ぶ `app=web` は別のものです。

## Step 2: Deployment と ClusterIP Service を作る

[`00-web-app.yaml`](../manifests/web/00-web-app.yaml) は変数展開不要です。Namespace、ConfigMap、Deployment、Service の 4 定義を含みます。

```bash
kubectl apply -f manifests/web/00-web-app.yaml
kubectl rollout status deployment/web -n web-lab --timeout=300s
kubectl get deployments,replicasets,pods,services -n web-lab -o wide
```

期待する状態:

| 対象 | 確認する値 |
|---|---|
| Deployment `web` | `READY` が `2/2` |
| Pod | 2 個が `Running`、`READY` はそれぞれ `1/1`、Node は webpool |
| Service `web` | `TYPE` が `ClusterIP`、`PORT(S)` が `80/TCP` |

Service の `EXTERNAL-IP` が `<none>` なのは正常です。まだインターネット公開していません。

```bash
kubectl get pods -n web-lab -l app=web --show-labels
kubectl get endpointslices -n web-lab \
  -l kubernetes.io/service-name=web -o yaml
```

EndpointSlice の `addresses` が Web Pod の IP と対応し、`conditions.ready` が `true` であることを確認します。selector が一致していなければ接続先は登録されません。

## Step 3: 公開せずに HTTP 応答を確認する

ターミナル A:

```bash
kubectl port-forward -n web-lab service/web 8080:80
```

ターミナル B（同じ実行端末）:

```bash
curl --fail --show-error http://127.0.0.1:8080/
```

`AKS Web Lab v1` を含む HTML が返れば成功です。ローカルで操作していればブラウザーでも同じ URL を開けます。SSH 先で実行している場合は、その端末で curl を使うか VS Code のポート転送を使います。安易に `--address 0.0.0.0` で公開しないでください。

port-forward は試験用の接続です。次は cluster 内から Service の DNS 名に接続し、Service 経由の通信も確認します。

```bash
kubectl run web-client -n web-lab \
  --image=nginxinc/nginx-unprivileged:1.28-alpine \
  --restart=Never --attach=true --rm \
  --command -- wget -qO- http://web.web-lab.svc.cluster.local/
```

同じ HTML が返ることを確認します。この一時 Pod は終了後に削除されます。通信できない場合は次の Step に進まず、[問題解決](09-troubleshooting-cleanup.md)の Web 項目を確認します。

```bash
kubectl logs -n web-lab -l app=web --prefix --tail=20
```

アクセスログや probe による `GET /` が表示されます。

## Step 4: 任意で Azure Load Balancer 経由の公開を試す

**公開 IP と Load Balancer には料金が発生し得ます。** 組織で公開が禁止されている場合は、この Step を省略して構いません。TLS・認証なしのテスト HTML だけを使い、機密データや本番アプリは配置しないでください。

公開範囲は操作端末の送信元グローバル IPv4 に限定します。VPN / NAT 利用時は Azure から見える送信元 IP を管理者に確認します。以下の例示 IP を実際の値へ置き換えます。`0.0.0.0/0` にはしません。

```bash
export WEB_ALLOWED_CIDR="203.0.113.10/32"
: "${WEB_ALLOWED_CIDR:?送信元 IPv4 の CIDR を設定してください}"
mkdir -p rendered/web
envsubst '${WEB_ALLOWED_CIDR}' \
  < manifests/web/01-web-public.yaml \
  > rendered/web/01-web-public.yaml
cat rendered/web/01-web-public.yaml
```

`loadBalancerSourceRanges` が自分の値になっていることを確認して適用します。**例示の `203.0.113.10/32` のままでは接続できません。**

```bash
kubectl apply -f rendered/web/01-web-public.yaml
kubectl get service web-public -n web-lab --watch
```

`EXTERNAL-IP` が `<pending>` から実際の IP になるまで数分待ち、Ctrl+C で監視を止めます。割り当て後、許可した送信元から次を実行します。

```bash
WEB_IP=$(kubectl get service web-public -n web-lab \
  -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
: "${WEB_IP:?EXTERNAL-IP の割り当てを待ってください}"
curl --fail --show-error --connect-timeout 10 "http://${WEB_IP}/"
```

IP 取得直後は Load Balancer の構成反映待ちで失敗することがあります。Service の Event を確認して少し待ち、再度アクセスしてください。

`web` と `web-public` は同じ `app=web` の Pod を選びます。Deployment は増えず、通信口だけが増えます。AKS が管理する Load Balancer や Node の NSG は直接編集せず、Service の定義で管理します。

確認後、**公開口だけ**を削除します。ClusterIP と Web Pod は残ります。

```bash
kubectl delete service web-public -n web-lab
```

## Step 5: Pod の自己修復を観察する

ターミナル A の port-forward を Ctrl+C で止めてから実行します。トンネル接続先の Pod を削除すると port-forward も終了するためです。

```bash
kubectl get pods -n web-lab -l app=web
WEB_POD=$(kubectl get pods -n web-lab -l app=web \
  -o jsonpath='{.items[0].metadata.name}')
: "${WEB_POD:?Web Pod が存在することを確認してください}"
kubectl delete pod "$WEB_POD" -n web-lab
kubectl get pods -n web-lab -l app=web --watch
```

削除した名前とは異なる Pod が作られ、最終的に 2 個が Ready になります。Ctrl+C で監視を終了します。

```bash
kubectl rollout status deployment/web -n web-lab --timeout=300s
kubectl get service web -n web-lab
```

Service の名前と ClusterIP は変更されません。必要なら port-forward を再実行して HTTP 応答も確認します。Pod を削除することと、アプリを削除することは違います。

## Step 6: v2 へのローリング更新とロールバック

イメージのビルド操作は後の章で学ぶため、ここでは配信コンテンツの参照先を変更して Pod template の更新を学びます。HTML を ConfigMap に置くのは教材用です。実アプリのコードは通常イメージに含めます。

```bash
kubectl apply -f manifests/web/02-web-content-v2.yaml
kubectl patch deployment web -n web-lab --type strategic \
  --patch '{"spec":{"template":{"spec":{"volumes":[{"name":"content","configMap":{"name":"web-content-v2"}}]}}}}'
kubectl rollout status deployment/web -n web-lab --timeout=300s
kubectl get replicasets,pods -n web-lab
kubectl rollout history deployment/web -n web-lab
```

`maxSurge: 1` と `maxUnavailable: 0` により、新 Pod が Ready になってから旧 Pod を減らします。更新中は最大 3 個分の配置容量が必要です。障害やアプリの接続終了処理によっては通信が切れるため、無停止を保証する設定ではありません。

port-forward が残っていたら Ctrl+C で止め、**更新の完了後に**開始し直します。

```bash
kubectl port-forward -n web-lab service/web 8080:80
```

別ターミナルで curl を実行し、今度は `AKS Web Lab v2` が返ることを確認します。その後 port-forward を止め、元に戻します。

```bash
kubectl rollout undo deployment/web -n web-lab
kubectl rollout status deployment/web -n web-lab --timeout=300s
```

再度 port-forward と curl で `AKS Web Lab v1` に戻ったことを確認します。

**ConfigMap 自体の内容を上書きしても Deployment の rollout undo はその内容を戻しません。** この教材は変更不可の `web-content-v1` と `web-content-v2` を別々に保持し、Pod template の参照先を変えるため、安全に比較できます。

## Step 7: Pod の台数を変更する

```bash
kubectl scale deployment web -n web-lab --replicas=3
kubectl rollout status deployment/web -n web-lab --timeout=300s
kubectl get pods -n web-lab -l app=web -o wide
kubectl get nodes -L agentpool,workload
```

期待する状態は **3 Pod、webpool は 1 Node のまま**です。Pod に要求した CPU / メモリが収まる限り、同じ Node に複数 Pod が配置されます。容量不足時は Pending になります。この章の webpool は Autoscaler を有効にしていないため、Node は自動追加されません。

```bash
kubectl scale deployment web -n web-lab --replicas=2
kubectl rollout status deployment/web -n web-lab --timeout=300s
```

`kubectl scale` は API 上の状態を変えますが、元の YAML の `replicas: 2` は書き換えません。元の Manifest を再適用すればその定義に戻ります。本番では Git / IaC などで定義を一元管理します。

### HPA と KEDA の違い

この章は **手動スケール**の演習で、HPA は作成していません。

| 機能 | 増減するもの | 典型的な判断材料 |
|---|---|---|
| HPA | Deployment の Pod 数 | CPU 利用率など。CPU 利用率では requests とメトリクス収集が必要 |
| KEDA ScaledJob | 処理を完了する Job | Queue のメッセージ数 |
| Cluster Autoscaler | AKS 管理 node pool の Node 数 | リソース不足で配置できない Pod など |

本番 Web では HPA と Node の Autoscaler を組み合わせられます。第 6 章ではバッチ側で、KEDA と Cluster Autoscaler の 2 層を実際に観察します。

## Step 8: Web 環境だけを片付け、バッチへ進む

port-forward を止めます。この教材で作成した専用 Namespace と専用 pool だけを削除します。共有環境では同名の別用途リソースがないことを先に確認してください。

```bash
kubectl delete service web-public -n web-lab --ignore-not-found
kubectl delete namespace web-lab --wait=true

az aks nodepool delete \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$AKS_CLUSTER" \
  --name webpool
```

CLI に確認が表示されたら、対象名を確認して承認します。Namespace 削除だけでは VM の課金は止まりません。Node pool も削除したことを確認します。

```bash
az aks nodepool list \
  --resource-group "$RESOURCE_GROUP" \
  --cluster-name "$AKS_CLUSTER" \
  --query '[].{name:name,count:count}' --output table
```

一覧から `webpool` がなくなり、`systempool` と `batchpool` が残れば完了です。ACR、Storage、AKS cluster はバッチ演習で再利用するため、ここではリソースグループを削除しません。

次は[第 4 章: バッチのイメージと Workload Identity](04-image-and-identity.md)へ進みます。

## 完了チェック

- [ ] Deployment が Web Pod を 2 個維持し、Service 経由で v1 の HTML を取得できた
- [ ] 任意の公開演習を行った場合は公開 Service を削除した
- [ ] Pod の削除後に別 Pod が自動作成された
- [ ] v2 へ更新し、v1 へ戻せた
- [ ] 3 Pod に増やしても Node は 1 台のままだった
- [ ] Web Namespace と Web Node pool を削除し、バッチ用の環境を残した

## 公式資料

- [Kubernetes Services in AKS](https://learn.microsoft.com/azure/aks/concepts-network-services)
- [Azure Standard Load Balancer と AKS](https://learn.microsoft.com/azure/aks/load-balancer-standard)
- [Deployment の更新](https://kubernetes.io/docs/concepts/workloads/controllers/deployment/)
- [NGINX unprivileged image](https://github.com/nginx/docker-nginx-unprivileged)

この教材の image tag も更新される可能性があります。本番では脆弱性対応と更新試験を行い、検証した digest での固定を検討してください。
