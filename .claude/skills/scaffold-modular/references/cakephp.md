# CakePHP (モジュラモノリス) — 生成手順

対象: `services/cakephp-modular/`
ルール本文: `.claude/rules/30-cakephp-modular.md`（**先に読むこと**）
検証: `make verify-cakephp` / `depfile.yaml`

**deptrac は clean-arch-starter でも使っているが、軸が違う。**
あちらは「層」の依存方向、こちらは「機能モジュール」の境界。

## 雛形にする既存ファイル

既存モジュールは `modules/Identity/`, `modules/Storage/`, `modules/Archiving/`, `modules/Shared/`。

| 作るもの | 雛形の所在 |
|---|---|
| 公開 API | `modules/Identity/src/Public/IdentityApi.php` |
| 公開例外 | `modules/Identity/src/Exception/` |
| Table / Entity | `modules/Identity/src/Model/` |
| UseCase | `modules/Identity/src/UseCase/SignInUseCase.php` |
| Service | `modules/Identity/src/Service/` |
| Gateway | `modules/Identity/src/Gateway/` |
| プラグインクラス | `modules/Identity/src/IdentityPlugin.php` |
| イベント購読 | `modules/Archiving/src/Listener/IdentityEventListener.php` |
| 非同期ワーカー | `modules/Archiving/src/Command/DrainLogsCommand.php` |
| Controller | `src/Controller/Api/` |

## 新しいモジュールを作る手順

```
modules/<Name>/src/
├── Public/<Name>Api.php     ★ 外から触ってよい唯一の面
├── Exception/               ★ 例外も公開面の一部
├── Model/Table|Entity/      CakePHP ORM（内部実装）
├── UseCase/                 手順の組み立て（内部実装）
├── Service/                 内部実装
├── Gateway/                 AWS SDK（内部実装）
├── Listener/                他モジュールのイベント購読（必要なら）
└── <Name>Plugin.php         ★ 必須（後述）
```

その後、**3 箇所すべて**を更新する:

1. `depfile.yaml` に `<Name>Public` / `<Name>Internal` の 2 層を追加
2. `ruleset` に依存先を追加
3. `config/plugins.php` にプラグイン登録

**どれか 1 つでも漏れると、境界が検証されないまま動いてしまう。**

## depfile.yaml の否定先読み（最重要）

各モジュールを **Public / Internal の 2 層**に分けている。

```yaml
value: '^Identity\\(?!Public\\|Exception\\).*'
```

**この否定先読みが無いと `Identity\Public` も Internal に含まれ、判定が壊れる。**
新しいモジュールを足すときは必ずこの形を写す。

### 例外は公開面の一部

呼び出し側が catch すべき型を宣言できないと、契約として不完全になる。
そのため `Exception\` は Public 層に含めてある。
（内部実装が**自モジュールの**例外を投げるのは当然許可される）

## 公開 API の書き方

- クラス名は `<Name>Api`（例: `IdentityApi`）、名前空間は `<Name>\Public`
- **Entity を返さない。配列（値）を返す。**
  Entity を返すと呼び出し側がテーブル構造に依存する
- 公開面を増やしすぎない

## モジュール間は `Cake\Event` で繋ぐ

```
Identity  --dispatch("Identity.signIn")-->  [EventManager]
                                                  |
Archiving --Listener で購読 ---------------------+
```

- `Identity` の依存表は空のまま
- **イベント名は発行側と購読側に別々に書かれる。片方だけ変えると黙って届かなくなる**
  → 両者の一致を突き合わせるテストを必ず書く

## 非同期アーカイブはアウトボックス方式

**`cakephp/queue` は使えない。**
`symfony/config ^6|^7` を要求するが、CakePHP 5.4 は v8 を引くため依存解決できない（実際に踏んだ）。

依存を無理に下げるより、**DB へ一旦書いてワーカーが拾う**アウトボックス方式にしている。

- `pending_logs` テーブルへ書く（`ArchivingApi::recordLater()`）
- `bin/cake drain_logs` が拾って DynamoDB へ流す
- 失敗は `attempts` を増やして次回へ回す（**無限リトライを避ける**）

実案件でも一般的な形で、「アプリの書き込みと同じトランザクションに乗せられる」利点もある。

## ログの同期 / 非同期

| ログ | 方式 |
|---|---|
| 監査ログ（サインイン成功） | **同期**（`record()`） |
| 認証失敗 | **非同期**（`recordLater()`） |
| 操作ログ | **非同期** |

**失敗の記録で本体を落とさない。**

## CakePHP 固有のハマりどころ（すべて実際に踏んだもの）

- **`ext-intl` が必須。** composer 公式イメージには入っておらず、
  `composer install` が解決に失敗する。
- **`utf8mb4` は MySQL 固有。** PostgreSQL では `utf8`。
  取り違えると `client_encoding` のエラーで接続できない。
- **`respond()` で `autoRender` を切る。** 切らないとテンプレートを探しに行き、
  API しか無いアプリでは "Missing Template" になる。
- **CSRF 対策を `/api` 配下に適用しない。** JWT でステートレス認証するため
  CSRF の前提が成立しない。適用すると POST が
  "Missing or incorrect CSRF cookie type" で落ちる。
- **CakePHP 5.3+ はプラグインクラス無しの読み込みが deprecated。**
  警告がレスポンスに混ざり **JSON が壊れる**。
  **各モジュールに `<Module>Plugin` クラスを置くこと。**
- **モジュールをプラグイン登録しないと `fetchTable('Identity.Users')` が解決できない。**
  Command も検出されない。

## ベースライン

`skip_violations` は現在**空**。これは「完全準拠している」状態を表す。

- 既存コードを移行するときのみ登録してよい
- **新規コードの違反は登録しない。** 公開 API 経由に直す

## DynamoDB へ書く日時

`app-logs` テーブルは Rails / Phoenix と共有している。
SK は文字列で並ぶため、**タイムゾーン表記は `+00:00` に揃える**。

## Lambda での注意

- `/tmp` 以外書き込み不可。`CAKE_TMP=/tmp` を設定する。
- セッションを使わない（Cognito の JWT でステートレス検証）。
- アウトボックスのワーカーは EventBridge から定期起動する想定。

## 検証

```bash
make verify-cakephp
# 内訳: deptrac（モジュール境界）→ PHPUnit
```

PHPStan は `make verify-cakephp` に**含まれない**（CI の verify.yml でのみ走り、
そこでも `|| true` が付いている）。型を見たいときは個別に実行する。

```bash
docker compose run --rm --no-deps cakephp \
  ./vendor/bin/phpstan analyse --no-progress --memory-limit=512M
```

**`--memory-limit` は必須。** 既定の 128M ではワーカーがクラッシュし、
型エラーではなく `PHPStan process crashed` が出て解析が完走しない（実測）。

なお現状、既存コードに**型エラーが 2 件残っている**
（`ConnectionInterface::execute()` の未定義メソッド呼び出し等）。
CI の `|| true` はこれを通すためのもの。
**新しく書いたコードで PHPStan の指摘を増やさないこと** —
既存の 2 件に紛れさせない。

### ⚠ CakePHP のテストは現状 3 重に効いていない（実測）

**このスタックだけ、テストによる保証が他スタックと同等ではない。**
イベント連携を足すときに影響するので、先に把握しておくこと。

| # | 事実 | 影響 |
|---|---|---|
| 1 | Makefile の PHPUnit に `|| true` が付いている | テストが落ちても `make verify-cakephp` は**緑になる** |
| 2 | CI の verify.yml に PHPUnit ステップが**無い** | CI でもテストは走らない（走るのは deptrac と PHPStan だけ） |
| 3 | `modules/` 配下にテストが **1 件も無い** | 公開 API もイベント購読も、テストで守られていない |

さらに `--testsuite=app` が見るのは `tests/TestCase/` だけなので、
**モジュールにテストを置いても、スイート定義を足さない限り実行されない**
（`phpunit.xml` の `<testsuites>` に追加が要る）。

現状 `--testsuite=app` を実行すると **5 件失敗する**。内訳は全て CakePHP
スケルトン付属の `PagesControllerTest` で、**このリポジトリが書いたものではない**。
`/api` の CSRF を意図的に無効化している設計（上記「ハマりどころ」参照）と
スケルトンの前提が食い違うために落ちている。`|| true` はこれを通すためのもの。

### そのため、CakePHP でイベント連携を足すときは

1. テストを書く（他スタックと同じく必須。**書かないと何も守られない**）
2. **`phpunit.xml` の `<testsuites>` にモジュールのテストディレクトリを追加する**
3. **そのテストだけを名指しで実行し、緑を目視で確認する**

```bash
docker compose run --rm --no-deps cakephp \
  ./vendor/bin/phpunit modules/Archiving/tests/TestCase/Listener/
```

スイート全体（`--testsuite=app`）は既存の 5 件失敗に埋もれるため、
**新しいテストの成否を判断する材料にしない。**
`make verify-cakephp` が通ったことも、テストが通った証拠として扱わないこと。
