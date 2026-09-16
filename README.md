# modular-monolith-starter

**「層で切れないフレームワーク」で、構造を CI で強制するスターター。**

[clean-arch-starter](https://github.com/Akinori901/clean-arch-starter) の**対になるリポジトリ**です。

<p>
  <img alt="Ruby / Rails" src="https://img.shields.io/badge/Rails_8.1-modular_monolith-CC0000?logo=rubyonrails&logoColor=white">
  <img alt="packwerk" src="https://img.shields.io/badge/packwerk-境界検証-2ea44f">
  <img alt="CakePHP" src="https://img.shields.io/badge/CakePHP-予定-D33C43?logo=cakephp&logoColor=white">
  <img alt="Phoenix" src="https://img.shields.io/badge/Phoenix_1.8-Context-FD4F00?logo=elixir&logoColor=white">
  <img alt="boundary" src="https://img.shields.io/badge/boundary-境界検証-2ea44f">
  <img alt="AWS" src="https://img.shields.io/badge/AWS-Lambda_/_DynamoDB-232F3E?logo=amazonwebservices&logoColor=white">
  <img alt="License" src="https://img.shields.io/badge/License-MIT-green">
</p>

## なぜ2つに分かれているのか

「レイヤード化できないフレームワークは諦める」ではありません。**切り方の軸が違うだけ**です。

| | clean-arch-starter | 本リポジトリ |
|---|---|---|
| 対象 | 層で切れるフレームワーク | **層で切ると戦うことになるフレームワーク** |
| 切り方 | **層（水平）** | **機能パッケージ（垂直）** |
| 守るもの | 依存の**向き**（内側へのみ） | パッケージ間の**依存**と**公開面** |
| 破り方 | UseCase から Model を直接触る | 他パッケージの内部実装を直接触る |
| 例 | Go・Hanami・Laravel・Django・C# | **Rails・CakePHP・Phoenix** |

**どちらも「規約を文章ではなく CI で落ちる形にする」点は同じ**です。

### Rails に層を被せない理由

ActiveRecord は「Model が永続化を知っている」ことを前提に設計されています。
`User.where(...)` も `user.save!` もモデルの責務であり、ここに Repository 層を挟むと、
Rails の恩恵（マイグレーション・アソシエーション・スコープ・ジェネレータ）を
すべて手放すことになります。

そこで **Rails ウェイに逆らわず、代わりに「誰がそのモデルを触ってよいか」を縛ります。**
これが Shopify 発の **packwerk** による機能パッケージ分割で、Rails の主流解です。

## 収録スタック

| スタック | 構成 | 検証ツール | 状態 |
|---|---|---|---|
| **Rails 8.1** | packwerk モジュラモノリス | packwerk | ✅ |
| CakePHP | モジュール + deptrac | deptrac | 予定 |
| **Phoenix 1.8** | **Context**（FW 標準の境界） | **boundary** | ✅ |

→ 選定の根拠は [docs/design-decision.md](docs/design-decision.md)

## 構成（Rails）

```
services/rails-modular/
├── app/                      # ルートパッケージ（Controller 等）
│   └── controllers/          # 各パッケージの公開 API を呼ぶだけ
└── packages/
    ├── shared/               # Rails の基底クラスのみ（継承のため）
    ├── identity/             # 認証（Cognito）
    │   ├── app/
    │   │   ├── public/identity/api.rb   # ★ 外から触ってよい唯一の面
    │   │   ├── models/                  # ActiveRecord（内部実装）
    │   │   ├── use_cases/               # 手順の組み立て（内部実装）
    │   │   ├── services/                # 内部実装
    │   │   └── gateways/                # AWS SDK（内部実装）
    │   └── package.yml                  # 依存先の宣言
    ├── storage/              # オブジェクトストレージ（S3）
    └── archiving/            # ログのアーカイブ（DynamoDB）
```

### パッケージ同士は依存しない

| パッケージ | 責務 | 依存先 |
|---|---|---|
| `identity` | サインイン・トークン検証・ユーザー解決 | shared のみ |
| `storage` | ファイルの保存・取得・署名付きURL | shared のみ |
| `archiving` | 監査/アクセスログの永続化と検索 | shared のみ |

連携が必要なときは **イベント**で繋ぎます。

```
identity  --publish("identity.sign_in")-->  [ActiveSupport::Notifications]
                                                     |
archiving --subscribe("identity.sign_in")------------+
```

`identity` が `archiving` を直接呼ぶと、認証が監査ログの都合に引きずられます。
イベント経由にすることで:

- `identity` の `dependencies` は空のまま（packwerk が保証）
- アーカイブを止めても認証は動く
- 購読者を増やしても `identity` は変わらない

## 実装している処理（認証 → アーカイブ）

```
POST /api/auth/sign-in     Cognito 認証 → users 解決 → 監査ログ(同期)
GET  /api/auth/me          トークン検証 → ユーザー返却
POST /api/files            S3 アップロード → 操作ログ(非同期)
GET  /api/files/presign    署名付き URL（本体をアプリで中継しない）
GET  /api/logs             DynamoDB から時系列で取得
GET  /api/health           DB / S3 / Cognito / DynamoDB の疎通
```

### ログの同期・非同期の使い分け

| ログ | 方式 | 理由 |
|---|---|---|
| 監査ログ（サインイン成功） | **同期** | 「誰がいつサインインしたか」は後から復元できない。書けなければ処理を失敗させる |
| 認証失敗 | **非同期** | 攻撃時に大量発生する。件数が読めないものでリクエストをブロックしない |
| 操作ログ（アップロード等） | **非同期** | 本体の処理は既に成功している。ログで応答を待たせない |

## 構成前提

| 対象 | ローカル | AWS |
|---|---|---|
| DB | PostgreSQL 17 | RDS PostgreSQL |
| オブジェクトストレージ | SeaweedFS（S3 API 互換） | S3 |
| ログアーカイブ | DynamoDB Local | DynamoDB（TTL で自動削除） |
| 認証 | cognito-local | Cognito User Pool |
| Rails | Docker コンテナ | Lambda（コンテナイメージ） |
| Phoenix | Docker コンテナ | OTP リリース（コンテナイメージ） |

ローカルと本番で**同じ SDK・同じコードパス**を通します。
差分は環境変数（エンドポイント URL）だけで吸収し、
アプリコードに `if Rails.env.development?` を書きません。

## クイックスタート

```bash
make up          # 全サービス起動（バケット・テーブルも自動作成）
make seed        # ローカル Cognito にプールとテストユーザーを作成
                 # → 出力された値を .env へ書き写す
make migrate     # DB マイグレーション
make verify      # パッケージ境界の検証 + 静的解析 + テスト
```

動作確認:

**API のパスとレスポンス形状は全スタックで揃えてあります。**
ポートを変えるだけで、同じ手順がそのまま通ります。

| スタック | ポート |
|---|---|
| Rails | 3000 |
| Phoenix | **4000** |

```bash
curl localhost:4000/api/health
# {"healthy":true,"components":[{"name":"database","state":"up"}, ...]}

TOKEN=$(curl -s -X POST localhost:4000/api/auth/sign-in \
  -H 'Content-Type: application/json' \
  -d '{"email":"taro@example.com","password":"Passw0rd!"}' | jq -r .access_token)

curl -H "Authorization: Bearer $TOKEN" localhost:4000/api/logs
```

## パッケージ境界の検証

```bash
$ bin/packwerk check
📦 Packwerk is inspecting 19 files
No offenses detected
```

違反すると落ちます。

```
Dependency violation: ::User belongs to 'packages/identity',
but 'packages/storage' does not specify a dependency on 'packages/identity'.
```

**この検証は実際に機能することを確認済みです。**
Controller から `Identity::Api` ではなく内部の `User` を直接参照すると落ち、
戻すと通ることを実機で確認しています。

### ベースライン運用

既存コードに後から入れる場合、`bin/packwerk update-todo` で既知違反を
`package_todo.yml` に登録して始められます。重要なのは運用ルールの方です。

- 既存の違反 → ベースラインに登録してよい
- **新規の違反 → 追加しない。** 該当箇所を公開 API 経由に直す

## 構成（Phoenix）— Context は FW 標準機能

**Phoenix では「機能で切れ」とフレームワーク自身が言っています。**

`mix phx.gen.context Accounts User users` が生成するのは、
`lib/app/accounts.ex`（公開 API）と `lib/app/accounts/user.ex`（内部）という
**機能で切った境界そのもの**です。

Rails が「主流のやり方（packwerk）を後から入れる」形なのに対し、
Phoenix は **標準の構成がそのままモジュラモノリス**になっています。
本リポジトリの主張に最も素直に合致するスタックです。

```
services/phoenix-context/
├── lib/
│   ├── app/
│   │   ├── identity.ex          # ★ 外から触ってよい唯一の面
│   │   ├── identity/            #   内部実装（外から参照するとコンパイルが落ちる）
│   │   │   ├── user.ex          #     Ecto スキーマ
│   │   │   ├── sign_in.ex       #     手順の組み立て
│   │   │   ├── cognito_gateway.ex #   AWS / JWT 検証
│   │   │   ├── tokens.ex        #   ☆ 値の構造体（exports）
│   │   │   └── user_view.ex     #   ☆ 値の構造体（exports）
│   │   ├── storage.ex           # ★ 公開 API（S3）
│   │   ├── archiving.ex         # ★ 公開 API（DynamoDB）
│   │   └── repo.ex              # 全 Context が共有する接続プール
│   └── app_web/                 # Web 層（Controller / Router / Plug）
└── test/
```

### Context 同士は依存しない

| Context | 責務 | 依存先 |
|---|---|---|
| `AppWeb` | HTTP の入口。公開 API を呼ぶだけ | identity / storage / archiving |
| `App.Identity` | サインイン・トークン検証・ユーザー解決 | `App.Repo` のみ |
| `App.Storage` | ファイルの保存・取得・署名付きURL | **なし** |
| `App.Archiving` | 監査/アクセスログの永続化と検索 | **なし** |

連携は **イベント**で繋ぎます。

```
identity  --:telemetry.execute([:app,:identity,:sign_in])-->  [計測バス]
                                                                   |
archiving --:telemetry.attach_many で購読 --------------------------+
```

`Phoenix.PubSub` ではなく `:telemetry` を採ったのは、**監査ログを同期で
書きたい**からです。PubSub は配送が非同期で「届いたか」を発行側が知れません。
`:telemetry` は発行側のプロセス上で同期実行されるため、
**依存を切ったまま同期の成否を受け取れます**
（Rails の `ActiveSupport::Notifications` と同じ位置づけ）。

## Context 境界の検証（boundary）

**packwerk と違い、boundary は「コンパイラ」として動きます。**
境界違反はコンパイル警告として出るため、
`mix compile --warnings-as-errors` がそのまま境界検証になります。

```elixir
defmodule App.Identity do
  use Boundary,
    top_level?: true,
    type: :strict,               # 依存を一切継承しない
    deps: [App.Repo, Ecto, ExAws, Joken, Jason, Logger],
    exports: [Tokens, UserView]  # ここに書いたものだけが外から見える
end
```

`type: :strict` の副産物として、**外部ライブラリも `deps` に出ます**。
つまり宣言を読むだけで、その Context が持ち込む技術スタックが分かります。

```bash
$ mix boundary.spec
App.Identity
  exports: Tokens, UserView
  deps: App.Repo, Ecto, Ecto.Changeset, Ecto.Schema, ExAws, Jason, Joken, Logger

App.Archiving
  exports: LogEntry
  deps: ExAws, ExAws.Dynamo, Logger
```

`App.Identity` の deps に `App.Archiving` が**無い**ことが読めます。

### 違反すると落ちます

**この検証は実際に機能することを確認済みです。**
2 種類の違反を注入し、落ちること・戻すと通ることを実機で確認しています。

Web 層から Context の内部モジュール（exports 外）を呼ぶと:

```
warning: forbidden reference to App.Identity.User
  (module App.Identity.User is not exported by its owner boundary App.Identity)
  lib/app_web/controllers/session_controller.ex:51
```

identity から archiving を直接呼ぶと:

```
warning: forbidden reference to App.Archiving
  (references from App.Identity to App.Archiving are not allowed)
  lib/app/identity/sign_in.ex:39
```

いずれも `--warnings-as-errors` で exit 1 になります。

> **`--warnings-as-errors` を外すと検証は丸ごと素通りします。**
> Rails 版で `packwerk-extensions` を入れ忘れて `enforce_privacy` が
> 黙って無視された罠と同じ型なので、
> `test/boundary_test.exs` で「コンパイラが有効か」「宣言が意図どおりか」
> 自体もテストしています。

## AI 駆動開発での使い方

AI は「動くコード」を最短で書こうとするため、放っておくとパッケージ境界を貫通します。
そこで **規約を読ませ（rules）・手順を踏ませ（skill）・CI で落とす**、の三段で縛ります。

### 1. 規約を読ませる（`.claude/rules/`）

| ファイル | 適用範囲 |
|---|---|
| [`00-core.md`](.claude/rules/00-core.md) | 全体。**他のどの指示より優先される** |
| [`10-rails-modular.md`](.claude/rules/10-rails-modular.md) | Rails を触るとき |
| [`20-phoenix-context.md`](.claude/rules/20-phoenix-context.md) | Phoenix を触るとき |
| [`30-cakephp-modular.md`](.claude/rules/30-cakephp-modular.md) | CakePHP を触るとき |
| [`40-infra-cd.md`](.claude/rules/40-infra-cd.md) | インフラ / CD を触るとき |

### 2. 手順を踏ませる（`.claude/skills/scaffold-modular/`）

ルールは「何が禁止か」を定めますが、**それだけでは
AI が書き始める順序までは決まりません**。外側（Controller）から書き始めると、
内部実装を直接呼ぶのが最短になり、境界を壊す誘因がそこで生まれます。

[`scaffold-modular`](.claude/skills/scaffold-modular/SKILL.md) は、
コードを 1 行も書く前に **どのパッケージに属するか・公開面をどう変えるか**を
宣言させ、値の構造体 → モデル → 公開 API → 依存宣言 → Controller の順に書かせます。

Claude Code では、このリポジトリで作業を頼むと自動で起動します。

| ファイル | 内容 |
|---|---|
| [`SKILL.md`](.claude/skills/scaffold-modular/SKILL.md) | 全スタック共通の手順・禁止事項・イベント連携の作法 |
| [`references/rails.md`](.claude/skills/scaffold-modular/references/rails.md) | packwerk・`app/public/`・雛形の所在 |
| [`references/phoenix.md`](.claude/skills/scaffold-modular/references/phoenix.md) | boundary・`exports`・`top_level?` |
| [`references/cakephp.md`](.claude/skills/scaffold-modular/references/cakephp.md) | deptrac・否定先読み・アウトボックス |

### 3. 書かせた後に落とす（CI）

ルールを読ませても、AI は時々破ります。**破ったら `make verify` が落ちます。**
どの検証も「違反を注入したら実際に落ちること」を確認済みです。

## ライセンス

MIT
