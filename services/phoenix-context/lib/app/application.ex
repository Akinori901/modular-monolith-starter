defmodule App.Application do
  @moduledoc """
  OTP アプリケーションの起動。

  **ここだけが全 Context と Web 層の両方を知ってよい。**
  起動の一番外側でだけ配線するからこそ、Context 同士は
  互いを知らずに済む。

  `top_level?: true` で App のサブ境界から外している。
  名前空間の都合で `App.` の下にあるだけで、
  論理的には App / AppWeb と並ぶ位置にあるため。
  """

  # 起動のためだけに、各 Context と Web 層の両方に依存する。
  # 監督ツリーへ載せるのと購読を繋ぐのは起動側の責務なので、
  # ここだけが全体を知ってよい。**例外はこの1モジュールに閉じている。**
  #
  # ただし Context の**内部**モジュール（JwksCache / AsyncWriter /
  # IdentityEventSubscriber）は、それぞれの Context が
  # 「起動時に触ってよいもの」として export したものだけを使う。
  # 起動側だからといって内部を素通しにはしない。
  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [App.Identity, App.Storage, App.Archiving, App.Repo, AppWeb, Phoenix.PubSub]

  use Application

  @impl true
  def start(_type, _args) do
    children =
      [
        AppWeb.Telemetry,
        App.Repo,
        {Phoenix.PubSub, name: App.PubSub}
      ] ++
        # 各 Context が「自分に必要な常駐プロセス」を自分で答える。
        # 起動側は内部モジュールの名前を知らない。
        App.Identity.children() ++
        App.Archiving.children() ++
        [AppWeb.Endpoint]

    # Context 間のイベント購読をここで繋ぐ。
    #
    # **依存の向きを反転させるための仕組み。**
    # identity は archiving を知らないまま、archiving 側が
    # identity のイベントを購読する。
    #
    # 起動の一番外側でだけ両者を知る形にすることで、
    # Context 同士は互いを知らずに済む
    # （Rails 版の config/initializers/subscribers.rb と同じ役割）。
    App.Archiving.subscribe!()

    opts = [strategy: :one_for_one, name: App.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    AppWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
