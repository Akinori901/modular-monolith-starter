defmodule App.Identity.UserTest do
  @moduledoc """
  **スキーマにビジネスルールを持たせていることのテスト。**
  「サインインできるか」は User の責務であり、手順側の if ではない。
  """

  use AppTest.DataCase, async: true

  alias App.Identity.User

  defp user(attrs \\ %{}) do
    %User{id: "sub-1", email: "taro@example.com", display_name: "taro", active: true}
    |> struct(attrs)
  end

  test "有効なユーザーはサインインできる" do
    assert User.can_sign_in?(user())
  end

  test "無効化するとサインインできなくなる" do
    refute User.can_sign_in?(user(%{active: false}))
  end

  test "表示名は50文字まで" do
    changeset = User.changeset(%User{}, %{
      id: "sub-1",
      email: "taro@example.com",
      display_name: String.duplicate("あ", 51),
      active: true
    })

    refute changeset.valid?
    assert %{display_name: _} = errors_on(changeset)
  end

  test "メールアドレスは必須" do
    changeset = User.changeset(%User{}, %{id: "sub-1", display_name: "taro"})

    refute changeset.valid?
    assert %{email: _} = errors_on(changeset)
  end

  test "表示名の既定値はメールのローカル部（規則をスキーマに置く）" do
    assert User.default_display_name("taro@example.com") == "taro"
  end
end
