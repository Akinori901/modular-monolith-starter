# 30. CakePHP — モジュラモノリス構成ルール

対象: `services/cakephp-modular/`
検証: `deptrac`（`depfile.yaml`）+ PHPStan + PHPUnit

## なぜ層ではなくモジュールか

CakePHP は Rails と同系統の**フルスタック MVC**。
ただし ActiveRecord と違い、**Table（クエリ）と Entity（行）が
最初から分離している**ぶん、エンティティにルールを持たせやすい。

それでも層に切ると戦うことになる理由は Rails と同じ:

- Bake（ジェネレータ）が MVC 前提でコードを吐く
- ドキュメント・案件の慣習・既存コードがすべて MVC 前提
- Table を Repository で包むと、Behavior・アソシエーション・
  Finder といった CakePHP の資産を手放すことになる

そこで **CakePHP ウェイに逆らわず、代わりに「誰がその Table を
触ってよいか」を縛る**。これが本リポジトリの立場。

> Laravel も同じ「フルスタック MVC」だが、
> clean-arch-starter 側にクリーンアーキ版を置いている。
> Laravel は規約次第で層に切れるのに対し、CakePHP は
> Bake との結び付きが強く、モジュール分割のほうが素直に収まる。

## モジュール構成

```
services/cakephp-modular/
├── src/                        # アプリ本体
│   └── Controller/Api/         # 各モジュールの公開 API を呼ぶだけ
└── modules/
    ├── Identity/               # 認証（Cognito）
    │   └── src/
    │       ├── Public/IdentityApi.php   # ★ 外から触ってよい唯一の面
    │       ├── Exception/               # ★ 例外も公開面の一部
    │       ├── Model/Table|Entity/      # CakePHP ORM（内部実装）
    │       ├── UseCase/                 # 手順の組み立て（内部実装）
    │       └── Gateway/                 # AWS SDK（内部実装）
    ├── Storage/                # オブジェクトストレージ（S3）
    └── Archiving/              # ログのアーカイブ（DynamoDB）
```

### 各モジュールの責務

| モジュール | 責務 | 依存先 |
|---|---|---|
| （アプリ本体） | HTTP の入口。公開 API を呼ぶだけ | Identity / Storage / Archiving の Public |
| `Identity` | サインイン・トークン検証・ユーザー解決 | **なし** |
| `Storage` | ファイルの保存・取得・署名付きURL | **なし** |
| `Archiving` | 監査/アクセスログの永続化と検索 | **なし** |

**モジュール同士は依存しない。** 連携はイベントで繋ぐ（後述）。

## 依存ルール（deptrac が強制）

各モジュールを **Public / Internal の2層**に分けている。

- `Public\` と `Exception\` … 外から触ってよい面
- それ以外 … 内部実装

### 禁止事項（違反は CI で落ちる）

- ❌ 他モジュールの Table / Entity / UseCase / Gateway を直接参照する
  → **`Identity\Public\IdentityApi` だけを使う**
- ❌ 内部実装から他モジュールを参照する（連携はイベント経由）
- ❌ モジュール間で Entity をそのまま渡す
  → 公開 API は**配列（値）**を返す。Entity を返すと呼び出し側が
     テーブル構造に依存する
- ❌ 公開面を増やしすぎる。**公開面が広いほど内部を変えられなくなる**

### 例外は公開面の一部

呼び出し側が catch すべき型を宣言できないと、契約として不完全になる。
そのため `Exception\` は Public 層に含めてある。
逆に、内部実装が**自モジュールの例外**を投げるのは当然許可する。

### 否定先読みに注意

```yaml
value: '^Identity\\(?!Public\\|Exception\\).*'
```

これが無いと `Identity\Public` も Internal に含まれ、判定が壊れる。

## テストの置き場所（モジュール側に置く）

```
modules/<Name>/tests/TestCase/...
```

`tests/TestCase/`（アプリ本体）とは**別のスイート**になっている。

| スイート | 対象 |
|---|---|
| `--testsuite=app` | `tests/TestCase/`（アプリ本体） |
| `--testsuite=modules` | `modules/*/tests/TestCase/` |

**新しいモジュールを足したら `composer.json` の `autoload-dev` に
`<Name>\Test\` を追加すること。** 追加しないとテストクラスが解決されず、
「書いたのに実行されない」状態になる。

## モジュール間はイベントで繋ぐ

`Identity` が `Archiving` を直接呼ぶと、依存が生まれて認証が
監査ログの都合に引きずられる（deptrac が検知する）。

代わりに `Cake\Event` で publish / subscribe する。

```
Identity  --dispatch("Identity.signIn")-->  [EventManager]
                                                  |
Archiving --Listener で購読 ---------------------+
```

こうすると:
- `Identity` の依存表は空のまま
- アーカイブを止めても認証は動く
- 購読者を増やしても `Identity` は変わらない

**両者の接点はイベント名の文字列だけ**になる。

### 疎結合の代金（必ず払うこと）

イベント名は**発行側と購読側に別々に書かれる**（参照し合うと依存が生まれるため）。
発行側の定数は `Identity\UseCase\SignInUseCase`（内部実装）にあり、
購読側からは参照できない。**片方だけ変えると黙って届かなくなる。**

deptrac が見るのは「境界を越えていないか」であって、
「イベントが実際に繋がっているか」は見られない。

→ **イベントを追加・変更したら、両者の一致を突き合わせるテストを必ず書く。**
既存例: `modules/Archiving/tests/TestCase/Listener/IdentityEventListenerTest.php`

**依存を切ると、繋がっていることの保証は型ではなくテストが持つ。**

## 非同期アーカイブはアウトボックス方式

**`cakephp/queue` は使えない。**
`symfony/config ^6|^7` を要求するが、CakePHP 5.4 は v8 を引くため
依存解決できない（実際に踏んだ）。

依存を無理に下げるより、**DB へ一旦書いてワーカーが拾う**
アウトボックス方式にしている。

- `pending_logs` テーブルへ書く（`ArchivingApi::recordLater()`）
- `bin/cake drain_logs` が拾って DynamoDB へ流す
- 失敗は `attempts` を増やして次回へ回す（無限リトライを避ける）

実案件でも一般的な形で、「アプリの書き込みと同じトランザクションに
乗せられる」という利点もある。

## ログの同期 / 非同期の使い分け

| ログ | 方式 | 理由 |
|---|---|---|
| 監査ログ（サインイン成功） | **同期**（`record()`） | 失えば復元できない。書けなければ処理を失敗させる |
| 認証失敗 | **非同期**（`recordLater()`） | 攻撃時に大量発生する |
| 操作ログ（アップロード等） | **非同期** | 本体は既に成功している |

**失敗の記録で本体を落とさない。**

## CakePHP 固有のハマりどころ

すべて実際に踏んだもの。

- **`ext-intl` が必須。** composer 公式イメージには入っておらず、
  `composer install` が解決に失敗する。
- **`utf8mb4` は MySQL 固有。** PostgreSQL では `utf8`。
  取り違えると `client_encoding` のエラーで接続できない。
- **`respond()` で `autoRender` を切る。** 切らないとテンプレートを
  探しに行き、API しか無いアプリでは "Missing Template" になる。
- **CSRF 対策を `/api` 配下に適用しない。** JWT でステートレスに
  認証するため CSRF の前提が成立しない。適用すると POST が
  "Missing or incorrect CSRF cookie type" で落ちる。
- **CakePHP 5.3+ はプラグインクラス無しの読み込みが deprecated。**
  警告がレスポンスに混ざり **JSON が壊れる**。
  各モジュールに `<Module>Plugin` クラスを置くこと。
- **モジュールをプラグイン登録しないと `fetchTable('Identity.Users')` が解決できない。**
  Command も検出されない。

## Lambda での注意

- ファイルシステムは `/tmp` 以外書き込み不可。`CAKE_TMP=/tmp` を設定する。
- セッションを使わない（Cognito の JWT でステートレスに検証する）。
- アウトボックスのワーカーは EventBridge から定期起動する想定。
