defmodule App.Archiving.DynamoGateway do
  @moduledoc """
  DynamoDB とのやり取りを閉じ込める。

  ## テーブル設計（Rails 版と同一。同じ app-logs テーブルを共有する）

      PK = "<log_type>#<owner_id>"   例: "audit#user-123"
      SK = "<ISO8601 timestamp>#<uuid>"

  **時系列で引けることを優先した設計。**
  「あるユーザーの直近のログ」が SK の範囲検索だけで取れる。
  GSI を足さずに済むぶん、書き込みコストも低い。

  TTL 属性(expires_at)を付けており、保持期間を過ぎたものは
  DynamoDB 側が自動削除する（削除のためのバッチを書かない）。

  archiving Context の内部実装。Context の外からは見えない。
  """

  @doc "1件書き込む。"
  @spec put(String.t(), String.t(), map(), DateTime.t()) :: {:ok, String.t()} | {:error, term()}
  def put(log_type, owner_id, payload, occurred_at) do
    timestamp = iso8601(occurred_at)
    sk = "#{timestamp}##{uuid()}"

    item = %{
      "pk" => "#{log_type}##{owner_id}",
      "sk" => sk,
      "log_type" => to_string(log_type),
      "owner_id" => to_string(owner_id),
      "occurred_at" => timestamp,
      # TTL。保持期間を過ぎたら DynamoDB が勝手に消す。
      "expires_at" => DateTime.add(occurred_at, retention_days() * 86_400, :second)
                      |> DateTime.to_unix(),
      "payload" => stringify(payload)
    }

    table()
    |> ExAws.Dynamo.put_item(item)
    |> ExAws.request()
    |> case do
      {:ok, _} -> {:ok, sk}
      {:error, reason} -> {:error, {:archive_error, "アーカイブに失敗しました: #{inspect(reason)}"}}
    end
  end

  @doc "直近のログを新しい順に返す。"
  @spec query(String.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def query(log_type, owner_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    since = Keyword.get(opts, :since)

    base = [
      # 新しい順（SK の降順）
      scan_index_forward: false,
      limit: limit,
      expression_attribute_values: [pk: "#{log_type}##{owner_id}"],
      key_condition_expression: "pk = :pk"
    ]

    params =
      if since do
        base
        |> Keyword.put(:key_condition_expression, "pk = :pk AND sk >= :since")
        |> Keyword.update!(:expression_attribute_values, &(&1 ++ [since: iso8601(since)]))
      else
        base
      end

    table()
    |> ExAws.Dynamo.query(params)
    |> ExAws.request()
    |> case do
      {:ok, %{"Items" => items}} -> {:ok, Enum.map(items, &decode/1)}
      {:ok, _} -> {:ok, []}
      {:error, reason} -> {:error, {:archive_error, "検索に失敗しました: #{inspect(reason)}"}}
    end
  end

  @doc "疎通確認。"
  @spec ping() :: :ok | {:error, term()}
  def ping do
    table()
    |> ExAws.Dynamo.describe_table()
    |> ExAws.request()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:archive_error, inspect(reason)}}
    end
  end

  # ── 内部 ───────────────────────────────────────────────

  # ExAws.Dynamo は生の DynamoDB JSON（型タグ付き）を返す。
  # そのまま外へ出すと呼び出し側が AWS の表現を知ることになるため、
  # ここで素の値へ戻す。
  defp decode(item) when is_map(item), do: Map.new(item, fn {k, v} -> {k, decode_value(v)} end)

  defp decode_value(%{"S" => v}), do: v
  defp decode_value(%{"N" => v}), do: v
  defp decode_value(%{"BOOL" => v}), do: v
  defp decode_value(%{"NULL" => _}), do: nil
  defp decode_value(%{"M" => v}), do: decode(v)
  defp decode_value(%{"L" => v}), do: Enum.map(v, &decode_value/1)
  defp decode_value(v), do: v

  # Rails 版に合わせて秒以下6桁まで出す（SK の並び順を揃えるため）。
  defp iso8601(%DateTime{} = dt) do
    dt
    |> DateTime.shift_zone!("Etc/UTC")
    |> DateTime.truncate(:microsecond)
    |> DateTime.to_iso8601()
  end

  # DynamoDB は数値・真偽値もそのまま扱えるが、payload の形が
  # 呼び出し側でまちまちになるため、値は文字列へ寄せて安定させる。
  defp stringify(payload) do
    payload
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new(fn {k, v} -> {to_string(k), to_string(v)} end)
  end

  defp uuid, do: 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

  defp table, do: config()[:table]
  defp retention_days, do: config()[:retention_days]
  defp config, do: Application.fetch_env!(:app, :dynamodb)
end
