# 10. Rails — モジュラモノリス構成ルール

対象: `services/rails-modular/`
検証: `packwerk`（`packwerk.yml` + 各 `package.yml`）+ RuboCop + RSpec

## なぜ層ではなくパッケージか

**Rails にクリーンアーキテクチャを丸ごと被せるのは主流ではなく、
アンチパターン扱いされることが多い。**

ActiveRecord は「Model が永続化を知っている」ことを前提に設計されている。
`User.where(...)` も `user.save!` もモデルの責務であり、
ここに Repository 層を挟むと、Rails の恩恵（マイグレーション・
アソシエーション・スコープ・ジェネレータ）をすべて手放すことになる。

そこで **Rails ウェイに逆らわず、代わりに「誰がそのモデルを触ってよいか」を縛る**。
これが Shopify 発の **packwerk** による機能パッケージ分割で、Rails の主流解。

- ActiveRecord はそのまま使う（Repository で包まない）
- 代わりに **パッケージの外から内部実装を触れなくする**
- パッケージ間で見えるのは `app/public/` に置いたものだけ

## パッケージ構成

```
services/rails-modular/
├── app/                      # ルートパッケージ（Controller 等）
│   └── controllers/          # 各パッケージの公開 API を呼ぶだけ
└── packages/
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

### 各パッケージの責務

| パッケージ | 責務 | 依存先 |
|---|---|---|
| （ルート） | HTTP の入口。公開 API を呼ぶだけ | identity / storage / archiving |
| `identity` | サインイン・トークン検証・ユーザー解決 | **なし** |
| `storage` | ファイルの保存・取得・署名付きURL | **なし** |
| `archiving` | 監査/アクセスログの永続化と検索 | **なし** |

**パッケージ同士は依存しない。** 連携が必要なときはイベントで繋ぐ（後述）。

## 依存ルール（packwerk が強制）

`package.yml` の 2 つの設定が要:

- `enforce_dependencies: true` — 宣言していないパッケージを参照したら落ちる
- `enforce_privacy: true` — `app/public/` 以外を外から参照したら落ちる

### 禁止事項（違反は CI で落ちる）

- ❌ 他パッケージの Model / Service / Gateway / UseCase を直接参照する
  （例: Controller から `User.find` / `Identity::SignInUseCase.new`）
  → **`Identity::Api` だけを使う**
- ❌ `package.yml` の `dependencies` に無いパッケージを参照する
- ❌ パッケージ間で ActiveRecord オブジェクトを渡す
  → 公開 API は `UserView` のような **値の構造体**を返す。
     ActiveRecord を返すと、呼び出し側がテーブル構造に依存する
- ❌ 公開 API を増やしすぎる。**公開面が広いほど内部を変えられなくなる**

## パッケージ間はイベントで繋ぐ

`identity` が `archiving` を直接呼ぶと、依存が生まれて認証が
監査ログの都合に引きずられる（packwerk が検知する）。

代わりに `ActiveSupport::Notifications` で publish / subscribe する。

```
identity  --publish("identity.sign_in")-->  [通知バス]
                                                 |
archiving --subscribe("identity.sign_in")--------+
```

こうすると:
- `identity` の `package.yml` の `dependencies` は空のまま
- アーカイブを止めても認証は動く
- 購読者を増やしても `identity` は変わらない

**両者の接点はイベント名の文字列だけ**になる。

## UseCase 層について

各パッケージ内に **軽めの UseCase 層**を置く。ただし目的を取り違えないこと。

- **UseCase の役割は「手順の組み立て」だけ。**
- **ビジネスルールはモデルが持つ。**
  「サインインできるか」は `user.can_sign_in?`。UseCase に `if user.active?` と書かない。
  書き始めたら、モデルが貧血症になっている合図。
- Controller に全部書くと、同じ手順を Job や rake から呼びたくなったとき再利用できない。
  UseCase はそのための層であって、レイヤードアーキテクチャの再現ではない。

## ログのアーカイブ（同期 / 非同期の使い分け）

| ログ | 方式 | 理由 |
|---|---|---|
| 監査ログ（サインイン成功） | **同期**（`Api.record!`） | 「誰がいつサインインしたか」は後から復元できない。書けなければ処理を失敗させる |
| 認証失敗 | **非同期**（`Api.record_later`） | 攻撃時に大量発生する。件数が読めないものでリクエストをブロックしない |
| 操作ログ（アップロード等） | **非同期** | 本体の処理は既に成功している。ログで応答を待たせない |

**失敗の記録で本体を落とさない。** 認証失敗ログの書き込みが失敗しても、
401 を返す処理自体は続ける（ログには残す）。

## ベースライン運用

既存コードに後から入れる場合、`bin/packwerk update-todo` で既知違反を
`package_todo.yml` に登録して始めてよい。重要なのは運用ルールの方。

- 既存の違反 → ベースラインに登録してよい
- **新規の違反 → 追加しない。** 該当箇所を公開 API 経由に直す

## Lambda での注意

- ファイルシステムは `/tmp` 以外書き込み不可。`TMPDIR=/tmp` を設定する。
- セッションを使わない（Cognito の JWT でステートレスに検証する）。
- 非同期ジョブのワーカーは Lambda とは別に動かす（SQS + 別関数、または ECS）。
