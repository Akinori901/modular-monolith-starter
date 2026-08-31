defmodule App.Storage.StoredFile do
  @moduledoc """
  保存したファイルの情報。

  **S3 の生レスポンスを外へ出さない。**
  出すと呼び出し側が ExAws のレスポンス構造に依存する。
  """

  @enforce_keys [:key, :size, :content_type]
  defstruct [:key, :size, :content_type]

  @type t :: %__MODULE__{key: String.t(), size: non_neg_integer(), content_type: String.t()}

  @doc "API レスポンス用のマップ。キー名は Rails 版と揃える。"
  def to_map(%__MODULE__{} = file) do
    %{key: file.key, size: file.size, content_type: file.content_type}
  end
end
