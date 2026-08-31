import Config

# 外部サービスの設定を1か所に集約する。
#
# 各 Context が System.get_env を直接読むと、
# 「何を設定すれば動くのか」がコード全体に散らばって追えなくなる。
#
# endpoint 系はローカル（cognito-local / SeaweedFS / DynamoDB Local）を
# 指すときだけ設定する。本番では空にして AWS の既定エンドポイントを使う。
#
# **runtime.exs に置くのが要点。** config.exs はコンパイル時に評価されるため、
# ここに書くとビルド時の環境変数がイメージに焼き込まれてしまう。

if System.get_env("PHX_SERVER") do
  config :app, AppWeb.Endpoint, server: true
end

# 空文字は「未設定」として扱う。compose の変数展開で空が入ることがあり、
# 空のエンドポイントを SDK に渡すと接続先を見失う。
blank_to_nil = fn
  nil -> nil
  "" -> nil
  value -> value
end

region = System.get_env("AWS_REGION") || "ap-northeast-1"

config :app, :cognito,
  region: region,
  user_pool_id: System.get_env("COGNITO_USER_POOL_ID") || "",
  client_id: System.get_env("COGNITO_CLIENT_ID") || "",
  client_secret: blank_to_nil.(System.get_env("COGNITO_CLIENT_SECRET")),
  endpoint: blank_to_nil.(System.get_env("COGNITO_ENDPOINT")),
  # エミュレータは自分の公開URL(localhost)を iss に刻む一方、
  # コンテナからは別ホスト名でしか到達できない。両者を分けて指定する。
  issuer_override: blank_to_nil.(System.get_env("COGNITO_ISSUER_OVERRIDE")),
  jwks_url_override: blank_to_nil.(System.get_env("COGNITO_JWKS_URL_OVERRIDE"))

config :app, :s3,
  region: region,
  bucket: System.get_env("S3_BUCKET") || "app-uploads",
  endpoint: blank_to_nil.(System.get_env("S3_ENDPOINT"))

config :app, :dynamodb,
  region: region,
  table: System.get_env("DYNAMODB_TABLE") || "app-logs",
  endpoint: blank_to_nil.(System.get_env("DYNAMODB_ENDPOINT")),
  # TTL。保持期間を過ぎたログは DynamoDB が自動削除する。
  retention_days: String.to_integer(System.get_env("LOG_RETENTION_DAYS") || "365")

# ── ExAws の接続先 ──
# ExAws はサービスごとに scheme / host / port を分けて持つ。
# URL 文字列をそのまま渡す形ではないため、ここで分解して入れる。
parse_endpoint = fn
  nil ->
    []

  url ->
    uri = URI.parse(url)
    [scheme: "#{uri.scheme}://", host: uri.host, port: uri.port]
end

config :ex_aws,
  access_key_id: [{:system, "AWS_ACCESS_KEY_ID"}, :instance_role],
  secret_access_key: [{:system, "AWS_SECRET_ACCESS_KEY"}, :instance_role],
  region: region

config :ex_aws,
       :s3,
       Keyword.merge(
         [region: region],
         parse_endpoint.(blank_to_nil.(System.get_env("S3_ENDPOINT")))
       )

config :ex_aws,
       :dynamodb,
       Keyword.merge(
         [region: region],
         parse_endpoint.(blank_to_nil.(System.get_env("DYNAMODB_ENDPOINT")))
       )

config :ex_aws,
       :"cognito-idp",
       Keyword.merge(
         [region: region],
         parse_endpoint.(blank_to_nil.(System.get_env("COGNITO_ENDPOINT")))
       )

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :app, App.Repo,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    socket_options: maybe_ipv6

  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  config :app, AppWeb.Endpoint,
    url: [host: System.get_env("PHX_HOST") || "example.com", port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: String.to_integer(System.get_env("PORT") || "4000")
    ],
    secret_key_base: secret_key_base
end
