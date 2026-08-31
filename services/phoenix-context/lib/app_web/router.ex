defmodule AppWeb.Router do
  use AppWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
  end

  # 認証が要る経路にだけ挟む。
  # **認証を「全体に掛けて例外を開ける」形にしない。**
  # 開け忘れより閉じ忘れの方が事故が重いので、明示的に足す。
  pipeline :authenticated do
    plug AppWeb.Plugs.Authenticate
  end

  # パスとレスポンス形状は Rails 版（config/routes.rb）に完全に揃える。
  # 同じ API を別スタックで実装したものであることが、比較の前提になる。
  scope "/api", AppWeb do
    pipe_through :api

    get "/health", HealthController, :show
    get "/health/live", HealthController, :live

    post "/auth/sign-in", SessionController, :create
  end

  scope "/api", AppWeb do
    pipe_through [:api, :authenticated]

    get "/auth/me", SessionController, :show

    post "/files", FileController, :create
    get "/files/presign", FileController, :show

    get "/logs", LogController, :index
  end
end
