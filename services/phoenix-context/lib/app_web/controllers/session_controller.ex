defmodule AppWeb.SessionController do
  @moduledoc """
  Controller がやってよいのは 3 つだけ:

    1. 入力の検証
    2. Context の公開 API 呼び出し
    3. 応答の組み立て（エラー値 → HTTP ステータスの変換）

  **触ってよいのは `App.Identity` だけ。**
  `App.Identity.User` や `App.Identity.SignIn` を直接呼ぶと
  boundary がコンパイル時に落とす。
  """

  use AppWeb, :controller

  alias App.Identity
  alias App.Identity.UserView

  def create(conn, %{"email" => email, "password" => password})
      when is_binary(email) and is_binary(password) do
    meta = %{ip: client_ip(conn), user_agent: user_agent(conn)}

    case Identity.sign_in(email, password, meta) do
      {:ok, %{tokens: tokens, user: user}} ->
        json(conn, %{
          access_token: tokens.access_token,
          id_token: tokens.id_token,
          refresh_token: tokens.refresh_token,
          expires_in: tokens.expires_in,
          user: UserView.to_map(user)
        })

      # 業務の語彙（認証失敗）を HTTP の語彙（401）へ翻訳するのはここ
      {:error, {:authentication_failed, message}} ->
        conn |> put_status(:unauthorized) |> json(%{detail: message})

      {:error, _reason} ->
        # 原因はログ側（Context）に残してある。レスポンスには出さない。
        conn |> put_status(:bad_gateway) |> json(%{detail: "認証基盤に接続できません"})
    end
  end

  def create(conn, params) do
    missing = Enum.find(~w[email password], &(not is_binary(params[&1])))
    conn |> put_status(:bad_request) |> json(%{detail: "#{missing} は必須です"})
  end

  def show(conn, _params) do
    # 認証は AppWeb.Plugs.Authenticate が済ませている。
    # ここに来た時点で current_user は必ずある。
    json(conn, UserView.to_map(conn.assigns.current_user))
  end

  defp client_ip(conn) do
    conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp user_agent(conn) do
    case Plug.Conn.get_req_header(conn, "user-agent") do
      [ua | _] -> ua
      [] -> nil
    end
  end
end
