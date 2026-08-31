defmodule App.Storage.S3Gateway do
  @moduledoc """
  S3（本番）/ SeaweedFS（ローカル）とのやり取りを閉じ込める。

  endpoint を差し替えるだけで両方に対応する。
  S3 互換 API を使う限り、コードは共通で済む。

  storage Context の内部実装。Context の外からは見えない。
  """

  @doc "オブジェクトを保存する。"
  @spec put(String.t(), binary(), String.t()) :: :ok | {:error, term()}
  def put(key, body, content_type) do
    bucket()
    |> ExAws.S3.put_object(key, body, content_type: content_type)
    |> request()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:storage_error, "アップロードに失敗しました: #{inspect(reason)}"}}
    end
  end

  @spec get(String.t()) :: {:ok, binary()} | {:error, term()}
  def get(key) do
    bucket()
    |> ExAws.S3.get_object(key)
    |> request()
    |> case do
      {:ok, %{body: body}} -> {:ok, body}
      {:error, {:http_error, 404, _}} -> {:ok, nil}
      {:error, reason} -> {:error, {:storage_error, "取得に失敗しました: #{inspect(reason)}"}}
    end
  end

  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(key) do
    bucket()
    |> ExAws.S3.delete_object(key)
    |> request()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:storage_error, "削除に失敗しました: #{inspect(reason)}"}}
    end
  end

  @doc """
  署名付き URL。**ファイル本体をアプリで中継しない**ための仕組み。
  中継すると BEAM のメモリと実行時間を無駄に食う。
  """
  @spec presigned_url(String.t(), non_neg_integer()) :: {:ok, String.t()} | {:error, term()}
  def presigned_url(key, expires_in) do
    ExAws.Config.new(:s3, aws_config())
    |> ExAws.S3.presigned_url(:get, bucket(), key, expires_in: expires_in)
  end

  @doc """
  疎通確認。オブジェクト一覧ではなく HEAD バケットを使う。
  必要な権限が最小で済み、バケットの中身の量に影響されない。
  """
  @spec ping() :: :ok | {:error, term()}
  def ping do
    bucket()
    |> ExAws.S3.head_bucket()
    |> request()
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, {:storage_error, inspect(reason)}}
    end
  end

  defp request(operation), do: ExAws.request(operation, aws_config())

  # SeaweedFS 等の S3 互換実装は**仮想ホスト形式に対応しない**。
  # path style を有効にしないと `bucket.host` 形式で組み立てられ、
  # 名前解決に失敗する。
  defp aws_config do
    endpoint = config()[:endpoint]

    base = [region: config()[:region]]

    if endpoint do
      uri = URI.parse(endpoint)

      base ++
        [
          scheme: "#{uri.scheme}://",
          host: uri.host,
          port: uri.port,
          # ← これが無いと SeaweedFS では動かない
          virtual_host: false
        ]
    else
      base
    end
  end

  defp bucket, do: config()[:bucket]

  defp config, do: Application.fetch_env!(:app, :s3)
end
