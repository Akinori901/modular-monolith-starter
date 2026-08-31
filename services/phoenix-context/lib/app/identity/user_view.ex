defmodule App.Identity.UserView do
  @moduledoc """
  Context の外へ出すユーザーの形。

  **Ecto スキーマ（App.Identity.User）をそのまま返さない。**
  返すと呼び出し側がテーブル構造に依存し、カラムを1つ変えるだけで
  Web 層まで壊れる。

  Rails 版の `Identity::Api::UserView` に相当する。
  """

  @enforce_keys [:id, :email, :display_name, :active]
  defstruct [:id, :email, :display_name, :active]

  @type t :: %__MODULE__{
          id: String.t(),
          email: String.t(),
          display_name: String.t(),
          active: boolean()
        }

  @doc "API レスポンス用のマップ。キー名は Rails 版と揃える。"
  def to_map(%__MODULE__{} = view) do
    %{
      user_id: view.id,
      email: view.email,
      display_name: view.display_name,
      is_active: view.active
    }
  end
end
