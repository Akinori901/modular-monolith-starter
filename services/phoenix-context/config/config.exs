import Config

config :app,
  ecto_repos: [App.Repo],
  generators: [timestamp_type: :utc_datetime]

config :app, AppWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: AppWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: App.PubSub

config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

# ── ExAws ──
# 実際の値は config/runtime.exs で環境変数から入れる。
# ここでは HTTP クライアントと JSON コーデックだけ固定する。
config :ex_aws,
  json_codec: Jason,
  http_client: ExAws.Request.Hackney

import_config "#{config_env()}.exs"
