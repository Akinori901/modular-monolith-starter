defmodule AppTest.ConnCase do
  @moduledoc """
  HTTP のテストの土台。

  Controller が「Context の公開 API を呼んで応答を組み立てるだけ」に
  なっているかを、実際のリクエストで確かめるために使う。
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      @endpoint AppWeb.Endpoint

      import AppTest.ConnCase
      import Plug.Conn
      import Phoenix.ConnTest
    end
  end

  setup tags do
    AppTest.DataCase.setup_sandbox(tags)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
