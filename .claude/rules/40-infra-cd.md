# 40. インフラ / CD ルール

対象: `docker/`, `.github/workflows/`

## 構成前提

| 対象 | ローカル | AWS |
|---|---|---|
| DB | PostgreSQL 17 | RDS PostgreSQL |
| オブジェクトストレージ | SeaweedFS (S3 API 互換) | S3 |
| ログアーカイブ | DynamoDB Local | DynamoDB（TTL で自動削除） |
| 認証 | cognito-local | Cognito User Pool |
| キュー | Redis + Sidekiq | ElastiCache / SQS |
| Rails | Docker コンテナ | **Lambda**（コンテナイメージ） |

**ローカルと本番で同じ SDK・同じコードパスを通すこと。**
`if Rails.env.development?` による分岐をアプリコードに書かない。
差分はすべて環境変数（エンドポイント URL）で吸収する。

### ポートについて

clean-arch-starter と**同時に起動できるよう**、ホスト側ポートをずらしてある。
コンテナ内のポートは標準のままなので、アプリの設定は変わらない。

| サービス | ホスト | コンテナ |
|---|---|---|
| Rails | 3000 | 3000 |
| PostgreSQL | 15432 | 5432 |
| SeaweedFS (S3) | 18333 | 8333 |
| DynamoDB Local | 18000 | 8000 |
| cognito-local | 19229 | 9229 |
| Redis | 16379 | 6379 |

## DynamoDB のテーブル設計

```
PK = "<log_type>#<owner_id>"      例: "audit#user-123"
SK = "<ISO8601 timestamp>#<uuid>"
```

**時系列で引けることを優先した設計。**
「あるユーザーの直近のログ」が SK の範囲検索だけで取れるため、
GSI を足さずに済み、書き込みコストも低い。

**TTL 属性（`expires_at`）を必ず付ける。**
保持期間を過ぎたものは DynamoDB が自動削除するため、
削除のためのバッチを書かなくて済む。付け忘れると課金が増え続ける。

## Lambda 配置の制約（アプリコードに効く）

- **書き込み可能なのは `/tmp` のみ。** `TMPDIR=/tmp` を設定する。
- **実行ごとにコンテナが再利用される。** グローバル変数に
  **リクエスト固有の状態を持たせない**。
- **タイムアウトは API Gateway 側 29 秒が上限。** 長時間処理は SQS へ逃がす。
- **セッションを使わない。** Cognito の JWT でステートレスに検証する。
- **非同期ジョブのワーカーは Lambda とは別に動かす**（SQS + 別関数、または ECS）。
  Sidekiq は常駐プロセス前提なので Lambda には載らない。

## CD の原則

- **AWS 認証は OIDC のみ。** アクセスキーを GitHub Secrets に置かない。
- **AWS の Secrets が未設定なら、デプロイ系ジョブはスキップする。**
  テンプレートを clone しただけの状態で CI が赤くなるのを避けるため。
  `verify`（規約検証）は Secrets の有無にかかわらず常に実行する。
- **`main` push が本番デプロイのトリガー。** それ以外のブランチはデプロイしない。
- **デプロイ前に必ず `verify` ジョブを通す。** 境界検証が落ちたらデプロイに進まない。
