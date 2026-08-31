defmodule AppWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :app

  # **セッションを使わない。** Cognito の JWT でステートレスに検証する。
  # Lambda / 複数ノードへ素直に載せるため、サーバ側に状態を持たない。

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug AppWeb.Router
end
