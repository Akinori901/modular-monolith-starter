import Config

# DB は Rails 版と同じ compose の db サービスを使い、**データベース名だけ分ける**。
# 同じ Postgres インスタンスに相乗りしつつ、スキーマは互いに干渉しない。
config :app, App.Repo,
  username: System.get_env("DB_USERNAME") || "app",
  password: System.get_env("DB_PASSWORD") || "app",
  hostname: System.get_env("DB_HOST") || "localhost",
  database: System.get_env("DB_NAME") || "app_phoenix_development",
  stacktrace: true,
  show_sensitive_data_on_connection_error: true,
  pool_size: 10

config :app, AppWeb.Endpoint,
  # コンテナ外（ホスト）から到達できるよう全インタフェースで待ち受ける
  http: [ip: {0, 0, 0, 0}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "rTALPdKpuNeVOCkclbBdS4MIjGRHFKG3H9UJyts90AVFee6/rQ4ti2+XcEgVGuFC",
  watchers: []

config :logger, :default_formatter, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
config :phoenix, :plug_init_mode, :runtime
