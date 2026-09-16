# Phoenix (Context) — 生成手順

対象: `services/phoenix-context/`
ルール本文: `.claude/rules/20-phoenix-context.md`（**先に読むこと**）
検証: `make verify-phoenix` / `use Boundary`

**このスタックは FW 標準の構成がそのままモジュラモノリスになっている。**
`mix phx.gen.context` が生成するのは「公開 API + 内部」という機能境界そのもの。
他スタックのように「主流のやり方を後から入れる」のではない。

## 雛形にする既存ファイル

| 作るもの | 雛形 |
|---|---|
| 公開 API（Context） | `lib/app/identity.ex` |
| Ecto スキーマ | `lib/app/identity/user.ex` |
| 値の構造体（exports） | `lib/app/identity/user_view.ex`, `tokens.ex` |
| 手順モジュール | `lib/app/identity/sign_in.ex` |
| Gateway | `lib/app/identity/cognito_gateway.ex` |
| 常駐プロセス | `lib/app/identity/jwks_cache.ex` |
| イベント発行 | `lib/app/identity/audit_publisher.ex` |
| イベント購読 | `lib/app/archiving/identity_event_subscriber.ex` |
| 非同期ワーカー | `lib/app/archiving/async_writer.ex` |
| Controller | `lib/app_web/controllers/session_controller.ex` |
| Plug | `lib/app_web/plugs/authenticate.ex` |

## 新しい Context を作る手順

```
lib/app/<context>.ex        ★ 公開 API（外から触ってよい唯一の面）
lib/app/<context>/          　 内部実装
```

公開 API の先頭に `use Boundary` を置く:

```elixir
use Boundary,
  top_level?: true,            # App のサブ境界にせず、フラットに並べる
  type: :strict,               # 依存を一切継承しない
  deps: [App.Repo, Ecto, ...], # 依存してよい境界（**外部ライブラリも含む**）
  exports: [UserView, Tokens]  # 外から見えるモジュール
```

### 4 つの設定の意味（どれも外さない）

| 設定 | 意味 | 外すとどうなるか |
|---|---|---|
| `top_level?: true` | Context をフラットに並べる | Web 層の `deps` が `[App]` 1行になり、**どの Context に依存しているかが宣言から消える** |
| `type: :strict` | 依存を継承しない | 親の依存が黙って流れ込み、**宣言していない依存が使えてしまう** |
| `deps:` | 依存してよい境界 | 宣言外を参照したら落ちる |
| `exports:` | 外から見えるモジュール | ここに無いものを外から参照したら落ちる（packwerk の `public/` 相当） |

`type: :strict` の副産物として、**外部ライブラリも `deps` に書く必要が出る**。
つまり **その Context が持ち込む技術スタックが宣言に出る** — これは利点。

```elixir
# identity が Joken(JWT) と ExAws を使っていることが、宣言だけで分かる
deps: [App.Repo, Ecto, Ecto.Changeset, Ecto.Schema, ExAws, Joken, Jason, Logger]
```

全体の依存表は `mix boundary.spec` で出力できる。

## 外部ライブラリを足したとき

`type: :strict` のため、**新しいライブラリを使ったら `deps:` に追加が必要**。

**`ExAws.Dynamo` / `ExAws.S3` は `ExAws` とは別の境界。**
`deps: [ExAws]` だけでは足りず、それぞれ書く（実際に踏んだ）。

## 公開 API の書き方

- **Ecto スキーマを Context 外へ返さない。**
  `UserView` のような値の構造体を返し、`exports` に載せる。
- **Web 層から `App.Repo` を直接触らない。** DB を触るのは Context の仕事。
- `exports` を増やしすぎない。**公開面が広いほど内部を変えられなくなる。**

## 手順モジュールの役割を取り違えない

- **役割は「手順の組み立て」だけ。**
- **ビジネスルールはスキーマが持つ。** 「サインインできるか」は `User.can_sign_in?/1`。
  手順側に `if user.active?` と書かない。書き始めたらスキーマが貧血症になっている合図。

## 常駐プロセスは Context が自分で答える

`App.Application` に `App.Identity.JwksCache` と直接書くと、内部実装が起動コードに漏れる。
**各 Context が `children/0` を公開し、起動側は中身を知らないままそれを並べる。**

```elixir
children = [...] ++ App.Identity.children() ++ App.Archiving.children() ++ [...]
```

## Context 間は `:telemetry` で繋ぐ

```
identity  --:telemetry.execute([:app,:identity,:sign_in])-->  [計測バス]
                                                                   |
archiving --:telemetry.attach_many で購読 --------------------------+
```

### `Phoenix.PubSub` を採らなかった理由

| | `Phoenix.PubSub` | `:telemetry` |
|---|---|---|
| 配送 | **非同期** | **同期**（発行プロセス上で実行） |
| 失敗の伝播 | 発行側に返らない | 購読側の例外を発行側で捕まえられる |

**監査ログを同期で書きたい**のが決め手。
「誰がいつサインインしたか」は後から復元できないため、書けなかったらサインイン自体を失敗させたい。
`:telemetry` は **依存を切ったまま同期の成否を受け取れる**。

### 疎結合の代金

イベント名は発行側と購読側に別々に書かれる。**片方だけ変えると黙って届かなくなる。**
→ `test/app/archiving/identity_event_subscriber_test.exs` で両者の一致を突き合わせる。
**イベントを足したら必ずこのテストも足す。**

## 非同期は `Task.Supervisor`（Sidekiq 相当を入れていない理由）

BEAM は軽量プロセスと Supervisor が処理系側にあるため、
**アプリと同じ VM 上で監督付きの非同期処理を回せる**（`App.Archiving.AsyncWriter`）。

足りなくなるのは次のどちらかが要るときだけ:
- 再起動を跨いだ永続化
- 複数ノードに跨る分配

そのときは Oban や SQS へ差し替える。**差し替えは `AsyncWriter` の中だけで済み、
`App.Archiving` の公開面は変わらない**（境界を切った効果）。

## テスト補助モジュールの置き場所

`ConnCase` は性質上 Web 層と Context の両方に触る。
`AppWeb` の一部にすると**本番コードの依存宣言にテスト用の依存が混ざる**。
→ `AppTest` 境界（`check: [in: false, out: false]`）に置く。
**本番コードの境界は緩めない。**

## ハマりどころ（すべて実際に踏んだもの）

- **`elixir:1.18-slim` に ca-certificates が入っていない。** `mix deps.get` が落ちる。
- **リリースの実行イメージは builder と同じ Debian に揃える。**
  glibc が古いと `beam.smp: GLIBC_2.38 not found` で起動しない。
- **`MIX_ENV` は `dev`。** Rails の `development` を写すと `config/development.exs` を探して落ちる。
- **postgrex は `~> 0.22`。** 最新に見える `1.0.0-rc.1` は **2016 年**放置の RC。
- **hackney は `~> 4.0`**（ex_aws 2.7 の要求）。記事にある `~> 1.18` を写すと解決に失敗。
- **ex_aws 同梱の `ExAws.Request.Hackney` は hackney 4.x の応答を取りこぼす。**
  `App.AwsHttpClient` を挿して `{:ok, status, headers}`（本文なし応答）も受ける。
- **Cognito Identity Provider の ex_aws パッケージは存在しない。**
  `ex_aws_cognito_identity` は Federated Identities という別サービス。
  必要な操作だけ `ExAws.Operation.JSON` で組み立てる。
- **cognito-local は例外を型付きで返さない。** エラーコード文字列で判定する。
- **cognito-local は `ExpiresIn` を返さないことがある。** 既定値でフォールバック。
- **SeaweedFS は仮想ホスト形式に対応しない。** `virtual_host: false` が要る。

## DynamoDB へ書く日時（**このスタック固有の罠**）

`app-logs` テーブルは Rails / CakePHP と共有している。SK は文字列で並ぶ。

**Elixir の `DateTime.to_iso8601/1` は UTC を `Z` で終えるが、Rails / CakePHP は `+00:00`。**
混ざると同じ瞬間でも `"Z"(90) > "+"(43)` で並びが崩れる。**`+00:00` に揃える。**

## Lambda での注意

- `/tmp` 以外書き込み不可。`TMPDIR=/tmp`。
- **`Task.Supervisor` の非同期処理はリクエスト終了後に消える可能性がある。**
  Lambda はレスポンス返却後に実行を凍結するため、非同期アーカイブが完走しないことがある。
  Lambda に載せるなら SQS へ逃がすか、同期で書く。

## 検証

```bash
make verify-phoenix
# 内訳: boundary（境界。mix compile --warnings-as-errors）→ Credo → ExUnit
```

**boundary はコンパイラとして動く。** 境界違反はコンパイル警告として出るため、
`mix compile --warnings-as-errors` がそのまま境界検証になる。
**このフラグを外すと検証が丸ごと素通りする。**
