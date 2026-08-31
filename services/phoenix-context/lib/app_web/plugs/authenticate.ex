defmodule AppWeb.Plugs.Authenticate do
  @moduledoc """
  Bearer トークンを検証し、`conn.assigns.current_user` に
  `App.Identity.UserView` を載せる。

  **失敗をここで受け止めきること。** 漏らすと 500 になり、
  認証エラーが障害として扱われてしまう（Rails 版で実際に踏んだ）。

  触ってよいのは `App.Identity` の公開 API だけ。
  `App.Identity.CognitoGateway` を直接呼ぶとコンパイル時に落ちる。
  """

  import Plug.Conn

  @unauthorized_message "認証が必要です"

  def init(opts), do: opts

  def call(conn, _opts) do
    with {:ok, token} <- bearer_token(conn),
         {:ok, user} <- App.Identity.current_user(token) do
      assign(conn, :current_user, user)
    else
      {:error, {:authentication_failed, message}} -> unauthorized(conn, message)
      {:error, _other} -> unauthorized(conn, @unauthorized_message)
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token | _] ->
        case String.trim(token) do
          "" -> {:error, {:authentication_failed, @unauthorized_message}}
          token -> {:ok, token}
        end

      _ ->
        {:error, {:authentication_failed, "Authorization ヘッダがありません"}}
    end
  end

  defp unauthorized(conn, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{detail: message}))
    |> halt()
  end
end
