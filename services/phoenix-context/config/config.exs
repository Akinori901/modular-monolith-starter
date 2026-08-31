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
# http_client を差し替えている理由は App.AwsHttpClient の @moduledoc を参照。
# 同梱の ExAws.Request.Hackney は hackney 4.x の3要素応答を取りこぼす。
config :ex_aws,
  json_codec: Jason,
  http_client: App.AwsHttpClient

import_config "#{config_env()}.exs"
