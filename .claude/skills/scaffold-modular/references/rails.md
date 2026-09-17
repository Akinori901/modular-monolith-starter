# Rails (packwerk) — 生成手順

対象: `services/rails-modular/`
ルール本文: `.claude/rules/10-rails-modular.md`（**先に読むこと**）
検証: `make verify-rails` / `packwerk.yml` + 各 `package.yml`

## 雛形にする既存ファイル

| 作るもの | 雛形 |
|---|---|
| 公開 API | `packages/identity/app/public/identity/api.rb` |
| モデル | `packages/identity/app/models/user.rb` |
| UseCase | `packages/identity/app/use_cases/identity/sign_in_use_case.rb` |
| Service | `packages/identity/app/services/identity/audit_recorder.rb` |
| Gateway | `packages/identity/app/gateways/identity/cognito_gateway.rb` |
| パッケージ宣言 | `packages/identity/package.yml` |
| Controller | `app/controllers/api/sessions_controller.rb` |
| イベント購読 | `config/initializers/subscribers.rb` |
| 公開 API のテスト | `spec/packages/identity/api_spec.rb` |
| イベント突き合わせテスト | `spec/packages/archiving/identity_event_subscriber_spec.rb` |

## 新しいパッケージを作る手順

```
packages/<name>/
├── app/
│   ├── public/<name>/api.rb   ★ 外から触ってよい唯一の面
│   ├── models/                 ActiveRecord（内部実装）
│   ├── use_cases/              手順の組み立て（内部実装）
│   ├── services/               内部実装
│   └── gateways/               AWS SDK（内部実装）
└── package.yml
```

`package.yml` は必ずこの 2 つを立てる:

```yaml
enforce_dependencies: true   # 宣言していないパッケージを参照したら落ちる
enforce_privacy: true        # app/public/ 以外を外から参照したら落ちる
dependencies:
  - packages/shared          # 基底クラス（ApplicationRecord / ApplicationJob）のみ
```

**`dependencies` は原則 `packages/shared` だけにする。**
他パッケージを足したくなったら、**まずイベントで繋げないかを考える**。

`packages/shared` が持つのは `ApplicationRecord` / `ApplicationJob` の基底クラスだけ。
**継承のための依存であって、機能的な結合ではない。**
共通処理の置き場として `shared` を太らせない（太らせると全パッケージが結合する）。

## 公開 API の書き方

- クラス名は `<Pkg>::Api`（例: `Identity::Api`）
- **ActiveRecord を返さない。** `UserView` のような値の構造体を返す
  （ActiveRecord を返すと、呼び出し側がテーブル構造に依存する）
- 公開面は最小限。**広いほど内部を変えられなくなる**

## UseCase の役割を取り違えない

- **UseCase は「手順の組み立て」だけ。**
- **ビジネスルールはモデルが持つ。** 「サインインできるか」は `user.can_sign_in?`。
  UseCase に `if user.active?` と書かない。書き始めたらモデルが貧血症になっている合図。
- Controller に全部書くと、同じ手順を Job や rake から呼べない。UseCase はそのための層。
  **レイヤードアーキテクチャの再現ではない。**

## パッケージ間はイベントで繋ぐ

`ActiveSupport::Notifications` で publish / subscribe する。

```
identity  --publish("identity.sign_in")-->  [通知バス]
                                                 |
archiving --subscribe("identity.sign_in")--------+
```

- 購読の登録は `config/initializers/subscribers.rb`
- **イベント名は発行側と購読側に別々に書かれる。片方だけ変えると黙って届かなくなる**
  → `spec/packages/archiving/identity_event_subscriber_spec.rb` で
     両者の一致を突き合わせる。**イベントを足したら必ずこのテストも足す**

## ログの同期 / 非同期

| ログ | 方式 |
|---|---|
| 監査ログ（サインイン成功） | **同期**（`Api.record!`） |
| 認証失敗 | **非同期**（`Api.record_later`） |
| 操作ログ（アップロード等） | **非同期** |

**失敗の記録で本体を落とさない。**

## packwerk が落ちたときの直し方

| 違反 | 意味 | 直し方 |
|---|---|---|
| Privacy | `app/public/` 以外を外から参照した | 公開 API 経由に直す。必要なら `Api` にメソッドを足す |
| Dependency | `package.yml` に無いパッケージを参照した | イベントで繋げないか先に検討。どうしても必要なら依存を宣言（理由をコメント） |

ベースライン（`bin/packwerk update-todo` → `package_todo.yml`）:

- 既存コードを移行するときのみ登録してよい
- **新規コードの違反は登録しない。** 公開 API 経由に直す

## 注意点

- packwerk 3.x では **privacy が本体から分離**されている。
  `packwerk.yml` の `require: packwerk-extensions` が無いと
  `enforce_privacy` が黙って無視される。
- 定数が解決できないと検査漏れになる。新しい autoload path を足したら
  `packwerk.yml` の `load_paths` にも追加する。

## DynamoDB へ書く日時

`app-logs` テーブルは **CakePHP / Phoenix と共有**している。
SK は文字列で並ぶため、**タイムゾーン表記は `+00:00` に揃える**（`Z` と混ぜると並びが崩れる）。

## Lambda での注意

- `/tmp` 以外書き込み不可。`TMPDIR=/tmp` を設定する。
- セッションを使わない（Cognito の JWT でステートレス検証）。
- 非同期ジョブのワーカーは Lambda とは別に動かす（SQS + 別関数、または ECS）。

## 検証

```bash
make verify-rails
# 内訳: packwerk（境界）→ RuboCop → RSpec → Brakeman
```
