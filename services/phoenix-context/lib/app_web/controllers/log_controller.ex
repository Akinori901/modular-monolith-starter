defmodule AppWeb.LogController do
  @moduledoc """
  アーカイブされたログの参照。
  """

  use AppWeb, :controller

  alias App.Archiving
  alias App.Archiving.LogEntry

  @max_limit 200
  @default_limit 50

  def index(conn, params) do
    user = conn.assigns.current_user
    log_type = Map.get(params, "log_type", Archiving.audit())

    case Archiving.recent(log_type, user.id, limit: limit(params)) do
      {:ok, entries} ->
        json(conn, %{entries: Enum.map(entries, &LogEntry.to_map/1)})

      {:error, {:archive_error, message}} ->
        conn |> put_status(:bad_gateway) |> json(%{detail: message})

      {:error, _reason} ->
        conn |> put_status(:bad_gateway) |> json(%{detail: "ログを取得できません"})
    end
  end

  # 上限を設けないと、1リクエストで全件走査させられる。
  defp limit(params) do
    params
    |> Map.get("limit")
    |> parse_limit()
    |> max(1)
    |> min(@max_limit)
  end

  defp parse_limit(nil), do: @default_limit

  defp parse_limit(value) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> @default_limit
    end
  end

  defp parse_limit(value) when is_integer(value), do: value
  defp parse_limit(_), do: @default_limit
end
