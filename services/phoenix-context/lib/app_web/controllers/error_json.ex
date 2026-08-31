defmodule AppWeb.ErrorJSON do
  @moduledoc """
  想定外の例外・未定義ルートのときの応答。

  **本文に原因を出さない。** スタックトレースや内部のメッセージを
  返すと、そのまま攻撃の材料になる。原因はログに残す。
  """

  def render(template, _assigns) do
    %{detail: Phoenix.Controller.status_message_from_template(template)}
  end
end
