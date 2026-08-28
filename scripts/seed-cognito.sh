#!/usr/bin/env bash
# ローカル Cognito（cognito-local）にユーザープールとテストユーザーを作る。
#
# 冪等: 既に存在する場合は作り直さない。
# 本番の Cognito には一切触れない（エンドポイントがローカル固定のため）。
set -euo pipefail

ENDPOINT="${COGNITO_ENDPOINT_URL:-http://localhost:9229}"
POOL_NAME="local_pool"
CLIENT_NAME="local-client"
TEST_EMAIL="${TEST_EMAIL:-taro@example.com}"
TEST_PASSWORD="${TEST_PASSWORD:-Passw0rd!}"

aws() { command aws --endpoint-url "$ENDPOINT" --region ap-northeast-1 "$@"; }
export AWS_ACCESS_KEY_ID=local AWS_SECRET_ACCESS_KEY=localsecret

echo "==> ユーザープールを確認"
POOL_ID=$(aws cognito-idp list-user-pools --max-results 20 \
  --query "UserPools[?Name=='${POOL_NAME}'].Id | [0]" --output text 2>/dev/null || echo "None")

if [ "$POOL_ID" = "None" ] || [ -z "$POOL_ID" ]; then
  # cognito-local は Id を指定して作れないため、生成された Id を控えて使う
  POOL_ID=$(aws cognito-idp create-user-pool --pool-name "$POOL_NAME" \
    --username-attributes email --query 'UserPool.Id' --output text)
  echo "    作成: $POOL_ID"
else
  echo "    既存: $POOL_ID"
fi

echo "==> アプリクライアントを確認"
CLIENT_ID=$(aws cognito-idp list-user-pool-clients --user-pool-id "$POOL_ID" --max-results 20 \
  --query "UserPoolClients[?ClientName=='${CLIENT_NAME}'].ClientId | [0]" --output text 2>/dev/null || echo "None")

if [ "$CLIENT_ID" = "None" ] || [ -z "$CLIENT_ID" ]; then
  CLIENT_ID=$(aws cognito-idp create-user-pool-client \
    --user-pool-id "$POOL_ID" --client-name "$CLIENT_NAME" \
    --explicit-auth-flows ALLOW_USER_PASSWORD_AUTH ALLOW_REFRESH_TOKEN_AUTH \
    --query 'UserPoolClient.ClientId' --output text)
  echo "    作成: $CLIENT_ID"
else
  echo "    既存: $CLIENT_ID"
fi

echo "==> テストユーザーを確認"
if ! aws cognito-idp admin-get-user --user-pool-id "$POOL_ID" --username "$TEST_EMAIL" >/dev/null 2>&1; then
  aws cognito-idp admin-create-user --user-pool-id "$POOL_ID" \
    --username "$TEST_EMAIL" --message-action SUPPRESS \
    --user-attributes Name=email,Value="$TEST_EMAIL" Name=email_verified,Value=true >/dev/null
  # 仮パスワード状態のままだとサインインで NEW_PASSWORD_REQUIRED になるため確定させる
  aws cognito-idp admin-set-user-password --user-pool-id "$POOL_ID" \
    --username "$TEST_EMAIL" --password "$TEST_PASSWORD" --permanent
  echo "    作成: $TEST_EMAIL"
else
  echo "    既存: $TEST_EMAIL"
fi

cat <<MSG

--------------------------------------------------------------
ローカル Cognito の準備ができました。以下を compose.yaml の
環境変数（django / laravel / frontend）へ反映してください。

  COGNITO_USER_POOL_ID=${POOL_ID}
  COGNITO_CLIENT_ID=${CLIENT_ID}

  テストユーザー: ${TEST_EMAIL} / ${TEST_PASSWORD}
--------------------------------------------------------------
MSG
