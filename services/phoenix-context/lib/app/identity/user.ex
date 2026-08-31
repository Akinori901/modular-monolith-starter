defmodule App.Identity.User do
  @moduledoc """
  Ecto スキーマ。

  **Phoenix ウェイに逆らわない。** Repository 層で包んだりしない。
  代わりに「このスキーマを誰が触ってよいか」を boundary が制御する。

  このモジュールは identity Context の内部実装であり、
  `App.Identity` の `exports` に載せていないため
  Context の外からは参照できない（コンパイル時に落ちる）。
  外へ見せるのは `App.Identity.UserView` だけ。
  """

  use Ecto.Schema
  import Ecto.Changeset

  # Cognito の sub を主キーにする（採番を Cognito に委ねる）
  @primary_key {:id, :string, autogenerate: false}
  @derive {Jason.Encoder, only: [:id, :email, :display_name, :active]}

  schema "users" do
    field :email, :string
    field :display_name, :string
    field :active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @doc """
  サインイン可能かを判定する（ビジネスルール）。

  この判定を Controller や Context の関数に `if` で書かないこと。
  スキーマ側に置かないと、同じ判定が各所へ散らばる。
  """
  def can_sign_in?(%__MODULE__{active: active}), do: active

  @doc "新規作成・更新用の changeset。"
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:id, :email, :display_name, :active])
    |> validate_required([:id, :email, :display_name])
    |> validate_length(:display_name, max: 50)
    |> unique_constraint(:email)
    |> unique_constraint(:id, name: "users_pkey")
  end

  @doc """
  メールアドレスから表示名の既定値を作る。

  Context 側で `String.split(email, "@")` を書くと、
  同じ規則が呼び出し箇所ごとに散らばる。
  """
  def default_display_name(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.slice(0, 50)
  end
end
