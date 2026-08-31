defmodule App.Identity.JwksCache do
  @moduledoc """
  JWKS（Cognito の公開鍵）のキャッシュ。

  検証のたびに取りに行くとレート制限に当たり、レイテンシも増える。
  ETS に載せて TTL で失効させる。

  identity Context の内部実装。Context の外からは見えない。
  """

  use GenServer

  @table __MODULE__
  # 鍵のローテーションに追随できる程度に短く、
  # かつ毎リクエスト取りに行かない程度に長く。
  @ttl_ms :timer.hours(12)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  URL から JWKS を取る。TTL 内ならキャッシュを返す。
  """
  @spec fetch(String.t()) :: {:ok, map()} | {:error, term()}
  def fetch(url) do
    case lookup(url) do
      {:ok, jwks} -> {:ok, jwks}
      :miss -> refresh(url)
    end
  end

  @doc "キャッシュを捨てる（テスト用）。"
  def invalidate, do: :ets.delete_all_objects(@table)

  @impl true
  def init(_opts) do
    # read_concurrency: 検証は並行に走るが書き込みは稀
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  defp lookup(url) do
    case :ets.lookup(@table, url) do
      [{^url, jwks, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at, do: {:ok, jwks}, else: :miss

      [] ->
        :miss
    end
  rescue
    # テスト等でプロセスが起動していない場合はキャッシュ無しで動かす
    ArgumentError -> :miss
  end

  defp refresh(url) do
    with {:ok, {{_, 200, _}, _headers, body}} <-
           :httpc.request(:get, {String.to_charlist(url), []}, [timeout: 5_000], []),
         {:ok, jwks} <- Jason.decode(to_string(body)) do
      put(url, jwks)
      {:ok, jwks}
    else
      _ -> {:error, :jwks_unavailable}
    end
  end

  defp put(url, jwks) do
    :ets.insert(@table, {url, jwks, System.monotonic_time(:millisecond) + @ttl_ms})
    :ok
  rescue
    ArgumentError -> :ok
  end
end
