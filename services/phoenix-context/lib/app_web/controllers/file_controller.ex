defmodule AppWeb.FileController do
  @moduledoc """
  S3 へのアップロードと、DynamoDB への操作ログ記録。

  **認証 → 保存 → アーカイブ**という流れを1本で示す。
  """

  use AppWeb, :controller

  alias App.Archiving
  alias App.Storage
  alias App.Storage.StoredFile

  def create(conn, %{"file" => %Plug.Upload{} = upload}) do
    user = conn.assigns.current_user

    with {:ok, body} <- File.read(upload.path),
         {:ok, stored} <-
           Storage.upload(user.id, upload.filename, body, content_type(upload)) do
      # 操作ログは**非同期**。アップロード自体は既に成功しているので、
      # ログの書き込みで応答を待たせない。
      Archiving.record_later(Archiving.operation(), user.id, %{
        event: "file_uploaded",
        key: stored.key,
        size: stored.size
      })

      conn |> put_status(:created) |> json(StoredFile.to_map(stored))
    else
      {:error, {:storage_error, message}} ->
        conn |> put_status(:bad_gateway) |> json(%{detail: message})

      {:error, _reason} ->
        conn |> put_status(:bad_gateway) |> json(%{detail: "アップロードに失敗しました"})
    end
  end

  def create(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{detail: "file は必須です"})
  end

  def show(conn, %{"key" => key}) when is_binary(key) do
    # ファイル本体をアプリで中継しない。署名付き URL を返して
    # クライアントに直接 S3 を叩かせる（帯域と実行時間の節約）。
    case Storage.presigned_url(key) do
      {:ok, url} -> json(conn, %{url: url})
      {:error, _} -> conn |> put_status(:bad_gateway) |> json(%{detail: "URL を発行できません"})
    end
  end

  def show(conn, _params) do
    conn |> put_status(:bad_request) |> json(%{detail: "key は必須です"})
  end

  defp content_type(%Plug.Upload{content_type: nil}), do: "application/octet-stream"
  defp content_type(%Plug.Upload{content_type: type}), do: type
end
