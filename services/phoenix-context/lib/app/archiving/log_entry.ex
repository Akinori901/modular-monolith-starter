defmodule App.Archiving.LogEntry do
  @moduledoc """
  アーカイブされたログ1件の形。

  **DynamoDB の生アイテムを外へ出さない。**
  出すと呼び出し側が pk / sk の組み立て規則に依存する。
  """

  @enforce_keys [:log_type, :owner_id, :occurred_at, :payload]
  defstruct [:log_type, :owner_id, :occurred_at, :payload]

  @type t :: %__MODULE__{
          log_type: String.t(),
          owner_id: String.t(),
          occurred_at: String.t(),
          payload: map()
        }

  @doc "API レスポンス用のマップ。キー名は Rails 版と揃える。"
  def to_map(%__MODULE__{} = entry) do
    %{
      log_type: entry.log_type,
      owner_id: entry.owner_id,
      occurred_at: entry.occurred_at,
      payload: entry.payload
    }
  end
end
