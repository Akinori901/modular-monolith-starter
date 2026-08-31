defmodule AppWeb do
  @moduledoc """
  Web 層（HTTP の入口）。

  **ここには業務のルールを置かない。** Controller がやってよいのは 3 つだけ:

    1. 入力の検証
    2. Context の公開 API 呼び出し
    3. 応答の組み立て（エラー値 → HTTP ステータスの変換）

  Context の内部モジュールを直接触るとコンパイル時に落ちる。
  """

  # Web 層は Context の**公開面だけ**に依存する。
  #
  # **deps に App.Repo が無いのが要点。**
  # Controller から `App.Repo.all(...)` のような直呼びはできない。
  # DB を触るのは Context の仕事であり、Web 層の仕事ではない。
  #
  # ここを読めば「Web 層がどの Context に依存しているか」が分かる。
  # 依存表を文章で別に持たず、コンパイラが読む場所に1つだけ置く。
  use Boundary,
    type: :strict,
    deps: [
      App.Identity,
      App.Storage,
      App.Archiving,
      Phoenix,
      Phoenix.PubSub,
      Plug,
      Jason,
      Logger,
      Telemetry.Metrics,
      Ecto.Adapters.SQL
    ],
    exports: [Endpoint]

  def static_paths, do: ~w(favicon.ico robots.txt)

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn

      unquote(verified_routes())
    end
  end

  def verified_routes do
    quote do
      use Phoenix.VerifiedRoutes,
        endpoint: AppWeb.Endpoint,
        router: AppWeb.Router,
        statics: AppWeb.static_paths()
    end
  end

  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
