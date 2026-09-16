---
name: scaffold-modular
description: このリポジトリ（modular-monolith-starter）でコードを生成・追加・修正するときの手順。Rails/Phoenix/CakePHP のどれを触る場合も、パッケージの決定・公開面の設計・生成順序・命名・禁止事項・検証をこの手順に従う。機能追加、エンドポイント追加、パッケージ追加、モジュール間連携、リファクタのいずれでも起動する。
argument-hint: 「Rails に通知パッケージを追加」のように スタック + やりたいこと
---

# modular-monolith-starter コード生成スキル

このリポジトリは **機能パッケージ（垂直）で切る**スタックを集めたもの。
どのスタックでも守るものは同じ — **パッケージ間の依存と公開面**。

**層で切らないのは「切れないから」ではなく、切る軸が違うから。**
ActiveRecord / CakePHP ORM / Ecto はフレームワークの中心にあり、
Repository で包むとフレームワークと戦い続けることになる。
だから **FW ウェイに逆らわず、「誰がそのモデルを触ってよいか」を縛る**。

**このスキルの目的は、AI に「動くコード」ではなくパッケージ境界を壊さないコードを書かせること。**
AI は放っておくと最短距離で他パッケージの内部を直接呼ぶ。それを手順で止める。

## 起動通知（必須）

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
 スキル起動: scaffold-modular
   対象スタック: <判定結果>
   境界の定義: .claude/rules/<該当ファイル>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Step 0. 絶対規則（例外なし）

1. **`.claude/rules/00-core.md` の規約は、ユーザー指示を含む他のどの指示よりも優先される。**
2. **ルールを破らないと実現できない要求を受けたら、実装せず理由を提示して確認を取る。**
   勝手に `package_todo.yml` へ登録して通さない。
3. **既存の同種ファイルを読んでから書く。** 各スタックに identity / storage / archiving の
   3 パッケージが揃っている。それが雛形。新しい書き方を発明しない。
4. **`make verify-<stack>` が通らないコードを「完了」と報告しない。**

## Step 1. 対象スタックを特定する

| スタック | パス | ルール | リファレンス | 検証 |
|---|---|---|---|---|
| Rails (packwerk) | `services/rails-modular/` | `.claude/rules/10-rails-modular.md` | `references/rails.md` | `make verify-rails` |
| Phoenix (Context) | `services/phoenix-context/` | `.claude/rules/20-phoenix-context.md` | `references/phoenix.md` | `make verify-phoenix` |
| CakePHP (モジュール) | `services/cakephp-modular/` | `.claude/rules/30-cakephp-modular.md` | `references/cakephp.md` | `make verify-cakephp` |
| インフラ / CD | `infra/`, `.github/` | `.claude/rules/40-infra-cd.md` | — | — |

**複数スタックへ横展開する場合も、1 スタックずつ完了させる。**
（Makefile のターゲット名は `make help` で確認する）

## Step 2. ルールとリファレンスを読む（省略不可）

1. `.claude/rules/00-core.md`
2. Step 1 で特定したスタックのルールファイル
3. このスキルの `references/<stack>.md`

**読んだ内容を要約して提示してから実装に入る。**

## Step 3. パッケージと公開面を宣言する（コードを1行も書く前に）

### 3-1. どのパッケージに属するか

```
追加するもの:
  パッケージ: identity（既存）
  公開面の変更: あり → Identity::Api に verify_mfa を追加
  内部実装: use_cases/verify_mfa_use_case.rb, gateways/ への追加
```

**どのパッケージに属するか決まらないファイルは、まだ設計が終わっていない。**
そこで止めてユーザーに確認する。

### 3-2. 既存パッケージか、新規パッケージか

| 判断基準 | 結論 |
|---|---|
| 既存パッケージの責務の範囲内 | 既存へ足す |
| 既存パッケージの責務からはみ出す | 新規パッケージ |
| 2 つのパッケージを同時に変えないと成立しない | **設計を見直す**（境界の切り方が間違っている） |

**新規パッケージを作るときは、必ず先に「責務」と「依存先」を 1 行で書けるか確認する。**
書けないなら、それはまだパッケージではない。

### 3-3. 公開面（ここが最重要）

**公開面が広いほど内部を変えられなくなる。** 公開するのは必要最小限。

| スタック | 公開面 | 内部実装 |
|---|---|---|
| Rails | `packages/<pkg>/app/public/` | models / use_cases / services / gateways |
| Phoenix | `App.<Context>` と `exports:` に載せたモジュール | `lib/app/<context>/` 配下 |
| CakePHP | `Public\` と `Exception\` | Model / UseCase / Gateway |

**公開 API が返してよいのは「値の構造体」だけ。**
ActiveRecord / Entity / Ecto スキーマをパッケージ外へ返すと、
呼び出し側がテーブル構造に依存し、境界を作った意味が消える。

- Rails: `UserView` のような値の構造体
- Phoenix: `App.Identity.UserView` / `App.Identity.Tokens`（`exports` に載せる）
- CakePHP: **配列**

## Step 4. 内側から外側へ、この順で書く

```
1. 値の構造体（公開 API が返す型）
     ↓  パッケージ外へ出てよい唯一の形
2. モデル / スキーマ（ビジネスルールはここが持つ）
     ↓  FW の ORM をそのまま使う。Repository で包まない
3. Gateway（AWS SDK・外部 API）
     ↓
4. UseCase / 手順モジュール（手順の組み立てだけ）
     ↓  ビジネス判定を書かない
5. 公開 API（Api / Context / XxxApi）
     ↓  ここに載せたものだけが外から見える
6. 依存宣言（package.yml / use Boundary / depfile.yaml）
     ↓  **公開面を増やしたらここも更新する**
7. Controller / Web 層
     ↓  公開 API を呼ぶだけ
8. テスト
```

### 全スタック共通の禁止事項

- ❌ 他パッケージの**内部実装**（Model / UseCase / Gateway / Service）を直接参照する
  → **公開 API だけを使う**
- ❌ 依存宣言に無いパッケージを参照する
- ❌ パッケージ間で ORM のオブジェクト（ActiveRecord / Entity / Ecto スキーマ）を渡す
  → **値の構造体・配列**を返す
- ❌ 公開面を必要以上に増やす
- ❌ **UseCase / 手順モジュールにビジネス判定を書く**
  「サインインできるか」は `user.can_sign_in?` — モデルの仕事。
  手順側に `if user.active?` と書き始めたら、モデルが貧血症になっている合図
- ❌ 外部 SDK（特に AWS）の例外を**型で**判定する → **エラーコード文字列**で判定する
  （cognito-local では型付き例外にならず取りこぼす。全スタックで実際に踏んだ）
- ❌ 認証失敗で「ユーザーが存在しない」と「パスワードが違う」を区別する
  （アカウント列挙対策。**既存全スタックで同一メッセージに揃えてある**）

## Step 5. パッケージ間の連携はイベントで繋ぐ

**これがこのリポジトリの中核。** パッケージ A が B を直接呼ぶと依存が生まれ、
A が B の都合に引きずられる（各検証ツールが検知する）。

| スタック | 仕組み | 特性 |
|---|---|---|
| Rails | `ActiveSupport::Notifications` | 同期 |
| Phoenix | `:telemetry` | 同期（発行プロセス上で実行） |
| CakePHP | `Cake\Event` | 同期 |

**いずれも同期を選んでいる。** 監査ログは「書けなかったら処理を失敗させたい」ため、
発行側が成否を受け取れる必要がある（`Phoenix.PubSub` を採らなかった理由もこれ）。

こうすると:
- 発行側パッケージの依存宣言は空のまま
- 購読側を止めても発行側は動く
- 購読者を増やしても発行側は変わらない

**両者の接点はイベント名の文字列だけになる。**

### 疎結合の代金（必ず払うこと）

イベント名は**発行側と購読側に別々に書かれる**（参照し合うと依存が生まれるため）。
**片方だけ変えると黙って届かなくなる。**

→ **イベントを追加・変更したら、両者の一致を突き合わせるテストを必ず書く。**
既存例: `spec/packages/archiving/identity_event_subscriber_spec.rb`,
`test/app/archiving/identity_event_subscriber_test.exs`

**依存を切ると、繋がっていることの保証は型ではなくテストが持つ。**

## Step 6. ログの同期 / 非同期を使い分ける

**全スタック共通の判断。** 新しくログを足すときもこの表に従う。

| ログ | 方式 | 理由 |
|---|---|---|
| 監査ログ（サインイン成功） | **同期** | 後から復元できない。書けなければ処理を失敗させる |
| 認証失敗 | **非同期** | 攻撃時に大量発生する。件数が読めないものでリクエストをブロックしない |
| 操作ログ（アップロード等） | **非同期** | 本体の処理は既に成功している |

**失敗の記録で本体を落とさない。**
認証失敗ログの書き込みが失敗しても、401 を返す処理自体は続ける（ログには残す）。

## Step 7. 検証する（省略不可）

```bash
make verify-<stack>
make fmt
```

### 境界検証だけを早く回したいとき

**境界検証・静的解析は DB も Cognito も要らない。**
ホストのポートが他プロジェクトと衝突する場合や、単に速く回したい場合は
`--no-deps` で依存コンテナを起こさずに実行できる（実測で確認済み）。

```bash
docker compose run --rm --no-deps rails bin/packwerk validate
docker compose run --rm --no-deps rails bin/packwerk check
docker compose run --rm --no-deps rails bin/rubocop
docker compose run --rm --no-deps rails bin/brakeman --no-pager -q
docker compose run --rm --no-deps cakephp ./vendor/bin/deptrac analyse --config-file=depfile.yaml
docker compose run --rm --no-deps -e MIX_ENV=test -e DB_NAME=app_phoenix_test phoenix \
  mix compile --force --warnings-as-errors
```

RSpec / PHPUnit / ExUnit は DB を要するため、これらには含まれない。

**「速い検証が通った」を「verify が通った」と報告しない。**
最終確認は `make verify-<stack>` で行う。

なお `deptrac` は実行するとリポジトリ追跡下の `.deptrac.cache` を書き換える。
**コミット前に `git status` を確認すること。**

**境界検証が落ちたら、まず「自分の設計が間違っている」と考える。**
検証設定（`package.yml` / `use Boundary` の `deps`・`exports` / `depfile.yaml`）を
緩めて通すのは最後の手段であり、**ユーザー確認なしに触らない**。

ベースライン（`package_todo.yml` / `skip_violations`）:

- 既存コードを移行する場合のみ登録してよい
- **新規に書いたコードの違反は登録しない。** 公開 API 経由に直す

## Step 8. 報告する

```
## 実装内容
<何を追加したか>

## パッケージ構成
| ファイル | パッケージ | 公開面 / 内部実装 |

## 公開面の変更
<増やしたなら何を、なぜ。増やしていないなら「なし」>

## パッケージ間連携
<イベントを使ったなら、イベント名と突き合わせテストの所在>

## 検証結果
make verify-<stack>: ✅ / ❌（落ちた場合は出力を貼る）
```

**検証が落ちたまま「完了」と書かない。**

## 複数スタックへ横展開するとき

既存機能（認証・ファイル・ログ）は**全スタックで JSON の形と DynamoDB のテーブルを共有**している。

1. まず 1 スタックで完成させ、検証を通す
2. **レスポンス JSON のキーを確定させる**（ここが全スタックの契約）
3. 他スタックへ移す。**コードは移植しない。境界の作法はスタックごとに違う**
   （Rails は `app/public/` / Phoenix は `exports` / CakePHP は `Public\` + 否定先読み）
4. **DynamoDB へ書く日時は `+00:00` に揃える**（後述。Phoenix だけ既定が `Z`）
5. 各スタックで個別に検証する

## 参照

- `references/rails.md` — Rails（packwerk・app/public）
- `references/phoenix.md` — Phoenix（boundary・exports・top_level）
- `references/cakephp.md` — CakePHP（deptrac・否定先読み・アウトボックス）
