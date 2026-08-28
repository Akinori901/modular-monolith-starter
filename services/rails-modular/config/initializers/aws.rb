# frozen_string_literal: true

# 外部サービスの設定を1か所に集約する。
#
# 各パッケージが ENV を直接読むと、
# 「何を設定すれば動くのか」がコード全体に散らばって追えなくなる。
#
# endpoint 系はローカル（cognito-local / SeaweedFS / DynamoDB Local）を
# 指すときだけ設定する。本番では空にして AWS の既定エンドポイントを使う。
Rails.application.configure do
  config.x.cognito = ActiveSupport::OrderedOptions.new.tap do |c|
    c.region = ENV.fetch("AWS_REGION", "ap-northeast-1")
    c.user_pool_id = ENV.fetch("COGNITO_USER_POOL_ID", "")
    c.client_id = ENV.fetch("COGNITO_CLIENT_ID", "")
    c.client_secret = ENV.fetch("COGNITO_CLIENT_SECRET", "")
    c.endpoint = ENV.fetch("COGNITO_ENDPOINT", "")
    # エミュレータは自分の公開URL(localhost)を iss に刻む一方、
    # コンテナからは別ホスト名でしか到達できない。両者を分けて指定する。
    c.issuer_override = ENV.fetch("COGNITO_ISSUER_OVERRIDE", "")
    c.jwks_url_override = ENV.fetch("COGNITO_JWKS_URL_OVERRIDE", "")
  end

  config.x.s3 = ActiveSupport::OrderedOptions.new.tap do |c|
    c.region = ENV.fetch("AWS_REGION", "ap-northeast-1")
    c.bucket = ENV.fetch("S3_BUCKET", "app-uploads")
    c.endpoint = ENV.fetch("S3_ENDPOINT", "")
  end

  config.x.dynamodb = ActiveSupport::OrderedOptions.new.tap do |c|
    c.region = ENV.fetch("AWS_REGION", "ap-northeast-1")
    c.table = ENV.fetch("DYNAMODB_TABLE", "app-logs")
    c.endpoint = ENV.fetch("DYNAMODB_ENDPOINT", "")
    # TTL。保持期間を過ぎたログは DynamoDB が自動削除する。
    c.retention_days = ENV.fetch("LOG_RETENTION_DAYS", "365")
  end
end
