#!/usr/bin/env bash
# S3 バケットと DynamoDB テーブルを作る。
#
# 冪等: 既に存在する場合は何もしない。
set -uo pipefail

S3_ENDPOINT="${S3_ENDPOINT:-http://storage:8333}"
DDB_ENDPOINT="${DYNAMODB_ENDPOINT:-http://dynamodb:8000}"
TABLE="${DYNAMODB_TABLE:-app-logs}"

echo "==> S3 バケット"
for b in app-uploads app-static; do
  aws --endpoint-url "$S3_ENDPOINT" s3 mb "s3://$b" 2>/dev/null \
    && echo "    作成: $b" || echo "    既存: $b"
done

echo "==> DynamoDB テーブル"
if aws --endpoint-url "$DDB_ENDPOINT" dynamodb describe-table --table-name "$TABLE" >/dev/null 2>&1; then
  echo "    既存: $TABLE"
else
  # PK = "<log_type>#<owner_id>" / SK = "<timestamp>#<uuid>"
  # 時系列で引けることを優先した設計。GSI を足さずに範囲検索できる。
  aws --endpoint-url "$DDB_ENDPOINT" dynamodb create-table \
    --table-name "$TABLE" \
    --attribute-definitions AttributeName=pk,AttributeType=S AttributeName=sk,AttributeType=S \
    --key-schema AttributeName=pk,KeyType=HASH AttributeName=sk,KeyType=RANGE \
    --billing-mode PAY_PER_REQUEST >/dev/null
  echo "    作成: $TABLE"

  # TTL。保持期間を過ぎたログは DynamoDB が自動削除する
  # （削除のためのバッチを書かずに済む）。
  aws --endpoint-url "$DDB_ENDPOINT" dynamodb update-time-to-live \
    --table-name "$TABLE" \
    --time-to-live-specification "Enabled=true,AttributeName=expires_at" >/dev/null 2>&1 \
    && echo "    TTL 有効化: expires_at"
fi

echo "==> 完了"
