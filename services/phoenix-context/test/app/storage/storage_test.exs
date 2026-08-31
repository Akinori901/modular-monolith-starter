defmodule App.StorageTest do
  @moduledoc """
  **公開 API が S3 の生レスポンスを返さないことのテスト。**
  """

  use ExUnit.Case, async: true

  alias App.Storage.StoredFile

  test "StoredFile は値の構造体で、Rails 版と同じキー名を返す" do
    file = %StoredFile{key: "uploads/u1/2026/08/31/x_a.txt", size: 3, content_type: "text/plain"}

    assert StoredFile.to_map(file) == %{
             key: "uploads/u1/2026/08/31/x_a.txt",
             size: 3,
             content_type: "text/plain"
           }
  end
end
