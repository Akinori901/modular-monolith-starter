import Config

config :app, App.Repo,
  username: System.get_env("DB_USERNAME") || "app",
  password: System.get_env("DB_PASSWORD") || "app",
  hostname: System.get_env("DB_HOST") || "localhost",
  database:
    (System.get_env("DB_NAME") || "app_phoenix_test") <> "#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :app, AppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "hILkEQlyJLHg/lbAO7UhtdJEqbHHyBVznCPhP6bCRcKz+15NJYMsVNbpshHbgmma",
  server: false

config :logger, level: :warning
config :phoenix, :plug_init_mode, :runtime

config :phoenix, sort_verified_routes_query_params: true
