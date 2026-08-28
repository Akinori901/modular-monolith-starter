# modular-monolith-starter

**「層で切れないフレームワーク」で、構造を CI で強制するスターター。**

[clean-arch-starter](https://github.com/Akinori901/clean-arch-starter) の**対になるリポジトリ**です。

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
| Phoenix (Elixir) | Context | 自作チェッカ + Credo | 予定 |

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

```bash
curl localhost:3000/api/health
# {"healthy":true,"components":[{"name":"database","state":"up"}, ...]}

TOKEN=$(curl -s -X POST localhost:3000/api/auth/sign-in \
  -H 'Content-Type: application/json' \
  -d '{"email":"taro@example.com","password":"Passw0rd!"}' | jq -r .access_token)

curl -H "Authorization: Bearer $TOKEN" localhost:3000/api/logs
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

## AI 駆動開発での使い方

`.claude/rules/` に規約を置き、CI で機械検証します。
AI は「動くコード」を最短で書こうとするため、放っておくとパッケージ境界を貫通します。

| ファイル | 適用範囲 |
|---|---|
| [`00-core.md`](.claude/rules/00-core.md) | 全体。**他のどの指示より優先される** |
| [`10-rails-modular.md`](.claude/rules/10-rails-modular.md) | Rails を触るとき |
| [`40-infra-cd.md`](.claude/rules/40-infra-cd.md) | インフラ / CD を触るとき |

## ライセンス

MIT
