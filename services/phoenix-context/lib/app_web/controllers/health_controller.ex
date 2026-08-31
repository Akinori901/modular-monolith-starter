defmodule AppWeb.HealthController do
  @moduledoc """
  各依存の疎通確認。

  **1つ落ちても残りは確認する。**
  全体像が見えないと切り分けができない。
  """

  use AppWeb, :controller

  alias App.{Archiving, Identity, Storage}

  # 名前は Rails 版（app/controllers/api/health_controller.rb）と揃える。
  # スタックが違ってもレスポンスの形が同じであることが比較の前提。
  @checks [
    {"database", &__MODULE__.check_database/0},
    {"object_storage", &Storage.ping/0},
    {"cognito", &Identity.ping/0},
    {"log_archive", &Archiving.ping/0}
  ]

  def show(conn, _params) do
    components = Enum.map(@checks, fn {name, check} -> probe(name, check) end)
    healthy? = Enum.all?(components, &(&1.state == "up"))

    # 依存が落ちていれば 503。ALB はステータスコードで判定するため、
    # 本文が返せていても 200 にしないこと。
    conn
    |> put_status(if healthy?, do: :ok, else: :service_unavailable)
    |> json(%{healthy: healthy?, components: components})
  end

  @doc "プロセスの生存のみを見る（依存を確認しない）。"
  def live(conn, _params), do: json(conn, %{status: "ok"})

  @doc false
  # DB の疎通だけは Context 越しに見るものが無いため、ここで直接見る。
  #
  # **Repo を Web 層から触っているように見えるが、そうではない。**
  # boundary の deps に App.Repo を入れていないので、
  # `App.Repo.query` を直接書くとコンパイルが落ちる。
  # 代わりに Ecto が公開しているアダプタ API を使う。
  def check_database do
    case Ecto.Adapters.SQL.query(App.Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp probe(name, check) do
    case run(check) do
      :ok -> %{name: name, state: "up", detail: ""}
      {:ok, _} -> %{name: name, state: "up", detail: ""}
      {:error, reason} -> %{name: name, state: "down", detail: truncate(reason)}
    end
  end

  # 疎通確認そのものが例外を投げても、ヘルスチェック全体を落とさない。
  # 落とすと「どこが悪いのか」を返せなくなる。
  defp run(check) do
    check.()
  rescue
    error -> {:error, Exception.message(error)}
  catch
    :exit, reason -> {:error, inspect(reason)}
  end

  defp truncate(reason) do
    reason |> to_detail() |> String.slice(0, 200)
  end

  defp to_detail(reason) when is_binary(reason), do: reason
  defp to_detail({_tag, message}) when is_binary(message), do: message
  defp to_detail(reason), do: inspect(reason)
end
