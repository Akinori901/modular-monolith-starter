defmodule AppTest.DataCase do
  @moduledoc """
  DB を触るテストの土台。

  トランザクションで囲って毎テスト巻き戻すため、
  テスト同士が互いのデータを見ない。
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      import AppTest.DataCase
      import Ecto.Changeset
      import Ecto.Query
    end
  end

  setup tags do
    setup_sandbox(tags)
    :ok
  end

  @doc "テストごとに DB のサンドボックスを張る。"
  def setup_sandbox(tags) do
    alias Ecto.Adapters.SQL.Sandbox

    pid = Sandbox.start_owner!(App.Repo, shared: not tags[:async])
    on_exit(fn -> Sandbox.stop_owner(pid) end)
  end

  @doc """
  changeset のエラーを `%{field: ["メッセージ"]}` の形にする。
  """
  def errors_on(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
      Regex.replace(~r"%{(\w+)}", message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
