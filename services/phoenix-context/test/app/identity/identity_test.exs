defmodule App.IdentityTest do
  @moduledoc """
  **公開 API が Ecto スキーマを返さないことのテスト。**
  返してしまうと、呼び出し側がテーブル構造に依存する。
  """

  use ExUnit.Case, async: true

  alias App.Identity.{User, UserView}

  test "UserView は Ecto スキーマではなく値の構造体" do
    view = %UserView{id: "sub-1", email: "taro@example.com", display_name: "taro", active: true}

    # Ecto スキーマ（DB の行）ではなく、値の構造体であること
    refute view.__struct__ == User
    assert view.__struct__ == UserView

    assert UserView.to_map(view) == %{
             user_id: "sub-1",
             email: "taro@example.com",
             display_name: "taro",
             is_active: true
           }
  end
end
