# 20. Phoenix — Context 構成ルール

対象: `services/phoenix-context/`
検証: `boundary`（各モジュールの `use Boundary`）+ Credo + ExUnit

## なぜ層ではなく Context か

**Phoenix では、この問いにフレームワーク自身が答えを出している。**

`mix phx.gen.context Accounts User users` が生成するのは、
`lib/app/accounts.ex`（公開 API）と `lib/app/accounts/user.ex`（内部）という、
**機能で切った境界そのもの**である。公式ガイドにも
"Contexts are dedicated modules that expose and group related functionality"
と書かれている。

つまり Rails のように「主流のやり方（packwerk）を後から入れる」のではなく、
**FW 標準の構成がそのままモジュラモノリスになっている**。
本リポジトリの主張に最も素直に合致するのがこのスタック。

- Ecto はそのまま使う（Repository で包まない）
- 代わりに **Context の外から内部モジュールを触れなくする**
- Context 間で見えるのは `exports` に載せたものだけ

Ecto は Rails の ActiveRecord と違い、スキーマとクエリが既に分かれている。
それでも層に切らないのは、**Phoenix が示している解が Context だから**であって、
「層に切れないから仕方なく」ではない。

## Context 構成

```
services/phoenix-context/
├── lib/
│   ├── app/                     # ビジネスロジック
│   │   ├── identity.ex          # ★ 公開 API（外から触ってよい唯一の面）
│   │   ├── identity/            #   内部実装
│   │   │   ├── user.ex          #     Ecto スキーマ
│   │   │   ├── sign_in.ex       #     手順の組み立て
│   │   │   ├── cognito_gateway.ex #   AWS / JWT
│   │   │   ├── jwks_cache.ex    #     常駐プロセス
│   │   │   ├── audit_publisher.ex #   イベント発行
│   │   │   ├── tokens.ex        #   ☆ 値の構造体（exports）
│   │   │   └── user_view.ex     #   ☆ 値の構造体（exports）
│   │   ├── storage.ex           # ★ 公開 API
│   │   ├── storage/             #   S3
│   │   ├── archiving.ex         # ★ 公開 API
│   │   ├── archiving/           #   DynamoDB
│   │   ├── repo.ex              # 全 Context が共有する接続プール
│   │   └── aws_http_client.ex   # ExAws の HTTP クライアント差し替え
│   └── app_web/                 # Web 層（Controller / Router / Plug）
└── test/
```

### 各 Context の責務

| Context | 責務 | 依存先 |
|---|---|---|
| `AppWeb` | HTTP の入口。公開 API を呼ぶだけ | identity / storage / archiving |
| `App.Identity` | サインイン・トークン検証・ユーザー解決 | `App.Repo` のみ |
| `App.Storage` | ファイルの保存・取得・署名付きURL | **なし** |
| `App.Archiving` | 監査/アクセスログの永続化と検索 | **なし** |
| `App.Repo` | DB 接続プール（土台） | **なし** |

**Context 同士は依存しない。** 連携が必要なときはイベントで繋ぐ（後述）。

## 依存ルール（boundary が強制）

各 Context の先頭に `use Boundary` を置く。要になるのは 4 つの設定。

```elixir
use Boundary,
  top_level?: true,   # App のサブ境界にせず、フラットに並べる
  type: :strict,      # 依存を一切継承しない
  deps: [App.Repo],   # 依存してよい境界（外部ライブラリも含む）
  exports: [Tokens, UserView]  # 外から見えるモジュール
```

- `deps` — 宣言していない境界を参照したら落ちる
- `exports` — ここに書いたもの**以外**を外から参照したら落ちる
  （packwerk の `app/public/` に相当）

### `top_level?: true` を付けている理由

boundary はモジュール名から境界を決めるため、素直に書くと
`App.Identity` は `App` の**サブ境界**になる。

サブ境界には「**外の境界から直接依存できない**」という制約があり、
Web 層の `deps` が `[App]` の 1 行になってしまう。
それでは「**Web 層がどの Context に依存しているか**」が宣言から消える。

依存表が読めなくなるのはこの構成で一番失いたくないものなので、
各 Context を top_level にしてフラットに並べている。

### `type: :strict` を付けている理由

これが無いと親の依存が黙って流れ込み、
**宣言していない依存が使えてしまう**。

副産物として、外部ライブラリも `deps` に書く必要が出る。
つまり **その Context が持ち込む技術スタックが宣言に出る**。

```elixir
# identity が Joken(JWT) と ExAws を使っていることが、宣言だけで分かる
deps: [App.Repo, Ecto, Ecto.Changeset, Ecto.Schema, ExAws, Joken, Jason, Logger]
```

`mix boundary.spec` で全体の依存表を出力できる。

### 禁止事項（違反は CI で落ちる）

- ❌ 他 Context の内部モジュールを直接参照する
  （例: Controller から `App.Identity.User` / `App.Identity.SignIn`）
  → **`App.Identity` だけを使う**
- ❌ `deps` に無い境界を参照する
- ❌ Context 間で Ecto スキーマを渡す
  → 公開 API は `UserView` のような **値の構造体**を返す。
     スキーマを返すと、呼び出し側がテーブル構造に依存する
- ❌ Web 層から `App.Repo` を直接触る。DB を触るのは Context の仕事
- ❌ `exports` を増やしすぎる。**公開面が広いほど内部を変えられなくなる**

## Context 間はイベントで繋ぐ

`identity` が `archiving` を直接呼ぶと、依存が生まれて認証が
監査ログの都合に引きずられる（boundary が検知する）。

```
identity  --:telemetry.execute([:app,:identity,:sign_in])-->  [計測バス]
                                                                   |
archiving --:telemetry.attach_many で購読 --------------------------+
```

こうすると:
- `App.Identity` の `deps` に archiving が入らない
- アーカイブを止めても認証は動く
- 購読者を増やしても identity は変わらない

**両者の接点はイベント名（アトムのリスト）だけ**になる。

### `:telemetry` を選び `Phoenix.PubSub` を採らなかった理由

| | `Phoenix.PubSub` | `:telemetry` |
|---|---|---|
| 配送 | **非同期**（購読プロセスへ send） | **同期**（発行プロセス上で実行） |
| 用途 | プロセス間のメッセージ配送 | 計測・監査の横断フック |
| 失敗の伝播 | 発行側に返らない | 購読側の例外を発行側で捕まえられる |

**監査ログを同期で書きたい**のが決め手。
「誰がいつサインインしたか」は後から復元できないため、
書けなかったらサインイン自体を失敗させたい（Rails 版と同じ判断）。

`Phoenix.PubSub` は配送が非同期なので、発行側は「届いたか」を知れない。
同期性が欲しければ発行側が購読プロセスの応答を待つ必要があり、
それは結局「呼び出し」に戻ってしまう。

`:telemetry` は発行側のプロセス上でハンドラを同期実行するため、
**依存を切ったまま同期の成否を受け取れる**。
Rails の `ActiveSupport::Notifications` と同じ位置づけで、移植としても素直。

### 疎結合の代金

依存を切った代償として、**イベント名は発行側と購読側に別々に書かれる**
（参照し合うと依存が生まれるため）。片方だけ変えると黙って届かなくなる。

そのため `test/app/archiving/identity_event_subscriber_test.exs` で
両者の一致を突き合わせている。**依存を切ると、繋がっていることの保証は
型ではなくテストが持つ**ことになる。

## 手順の組み立てについて

各 Context 内に **軽めの手順モジュール**を置く（`App.Identity.SignIn` など）。
ただし目的を取り違えないこと。

- **役割は「手順の組み立て」だけ。**
- **ビジネスルールはスキーマが持つ。**
  「サインインできるか」は `User.can_sign_in?/1`。
  手順側に `if user.active?` と書かない。書き始めたら、
  スキーマが貧血症になっている合図。
- Controller に全部書くと、同じ手順を Task や mix タスクから
  呼びたくなったとき再利用できない。この層はそのためにある。

## 常駐プロセスは Context が自分で答える

`App.Application` に `App.Identity.JwksCache` と直接書くと、
内部実装が起動コードに漏れる。各 Context が `children/0` を公開し、
起動側は中身を知らないままそれを並べる。

```elixir
children = [...] ++ App.Identity.children() ++ App.Archiving.children() ++ [...]
```

## ログのアーカイブ（同期 / 非同期の使い分け）

| ログ | 方式 | 理由 |
|---|---|---|
| 監査ログ（サインイン成功） | **同期**（`Archiving.record/3`） | 「誰がいつサインインしたか」は後から復元できない。書けなければ処理を失敗させる |
| 認証失敗 | **非同期**（`Archiving.record_later/3`） | 攻撃時に大量発生する。件数が読めないものでリクエストをブロックしない |
| 操作ログ（アップロード等） | **非同期** | 本体の処理は既に成功している。ログで応答を待たせない |

**失敗の記録で本体を落とさない。** 認証失敗ログの書き込みが失敗しても、
401 を返す処理自体は続ける（ログには残す）。

### Sidekiq 相当を入れていない理由

Rails 版は Sidekiq + Redis でワーカープロセスを分けている。
Ruby は「リクエストを処理するプロセスで重い仕事をさせられない」ため、
外部キューと常駐ワーカーがほぼ必須になる。

BEAM は軽量プロセスと Supervisor が言語処理系の側にあるため、
**アプリと同じ VM 上で監督付きの非同期処理を回せる**。
まず `Task.Supervisor` を採っている（`App.Archiving.AsyncWriter`）。

これで足りなくなるのは次のどちらかが要るときだけ:

- **再起動を跨いだ永続化**（プロセスが落ちたら積んだ仕事も消える）
- **複数ノードに跨る分配**

そのときは Oban（DB 永続キュー）や SQS へ差し替える。
差し替え先は `AsyncWriter` の中だけで済み、`App.Archiving` の公開面は変わらない。

## ハマりどころ

すべて実際に踏んだもの。

- **`elixir:1.18-slim` に ca-certificates が入っていない。**
  入れないと hex への TLS が失敗し `mix deps.get` が落ちる。
- **リリースの実行イメージは builder と同じ Debian に揃える。**
  リリースには builder 側の ERTS が入るため、実行側の glibc が古いと
  `beam.smp: ... version 'GLIBC_2.38' not found` で起動しない。
  `elixir:1.18-slim` は Debian 13(trixie/glibc 2.41)。
- **`MIX_ENV` は `dev`。** Rails の `development` を写すと
  `config/development.exs` を探しに行って落ちる。
- **postgrex は `~> 0.22` を使う。** hex 上の最新に見える `1.0.0-rc.1` は
  **2016 年**公開のまま放置された RC で、semver の並び順で先頭に来るだけ。
  `>= 0.0.0` のままにすると解決先が RC に振れうる。
- **hackney は `~> 4.0`。** ex_aws 2.7 の要求がこれ。
  記事によくある `~> 1.18` を写すと依存解決に失敗する。
- **ex_aws 同梱の `ExAws.Request.Hackney` は hackney 4.x の応答を取りこぼす。**
  `{:ok, status, headers}`（本文が無い応答＝HEAD 等）を受けておらず、
  `head_bucket` が `CaseClauseError` で落ちる。
  → `App.AwsHttpClient` を挿して両方の形を受ける。
- **`ExAws.Dynamo` / `ExAws.S3` は `ExAws` とは別の境界。**
  `deps: [ExAws]` だけでは足りず、それぞれ書く必要がある。
- **Cognito Identity Provider の ex_aws パッケージは存在しない。**
  `ex_aws_cognito_identity` は Federated Identities という別サービス。
  必要な操作だけ `ExAws.Operation.JSON` で組み立てる。
- **cognito-local は例外を型付きで返さない。** エラーコードの文字列で判定する。
- **cognito-local は `ExpiresIn` を返さないことがある。** 既定値でフォールバック。
- **SeaweedFS は仮想ホスト形式に対応しない。** `virtual_host: false` が要る。
- **DynamoDB の SK は文字列で並ぶ。**
  Elixir の `DateTime.to_iso8601/1` は UTC を `Z` で終えるが、
  Rails / CakePHP は `+00:00`。同じ app-logs テーブルを共有しているため、
  混ざると同じ瞬間でも `"Z"(90) > "+"(43)` で並びが崩れる。`+00:00` に揃える。
- **テスト補助モジュールは専用の境界へ逃がす。**
  `ConnCase` は性質上 Web 層と Context の両方に触るため、`AppWeb` の一部に
  すると本番コードの依存宣言にテスト用の依存が混ざる。
  `AppTest` 境界（`check: [in: false, out: false]`）に置く。
  **本番コードの境界は緩めないこと。**

## Lambda での注意

- ファイルシステムは `/tmp` 以外書き込み不可。`TMPDIR=/tmp` を設定する。
- セッションを使わない（Cognito の JWT でステートレスに検証する）。
- **`Task.Supervisor` の非同期処理はリクエスト終了後に消える可能性がある。**
  Lambda はレスポンス返却後に実行を凍結するため、
  非同期アーカイブが完走しないことがある。
  Lambda に載せるなら SQS へ逃がすか、同期で書くかを選ぶこと。
