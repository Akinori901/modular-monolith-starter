defmodule App.Identity.Tokens do
  @moduledoc """
  Cognito が発行したトークン一式。

  **公開する形は「値の構造体」にする。** Ecto スキーマや
  AWS の生レスポンスをそのまま返すと、呼び出し側がテーブル構造や
  AWS の JSON の形に依存してしまう。
  """

  @enforce_keys [:access_token, :id_token, :expires_in]
  defstruct [:access_token, :id_token, :refresh_token, :expires_in]

  @type t :: %__MODULE__{
          access_token: String.t(),
          id_token: String.t(),
          refresh_token: String.t(),
          expires_in: non_neg_integer()
        }
end
