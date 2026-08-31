defmodule App.Storage do
  @moduledoc """
  storage Context の**公開 API**。

  他 Context・Web 層から触ってよいのはこのモジュールと
  `App.Storage.StoredFile` だけ。
  `App.Storage.S3Gateway` は内部実装であり、外から参照すると
  コンパイル時に落ちる。

  identity に依存しない（誰がアップロードしたかは呼び出し側が決める）。
  """

  # top_level?: true — App のサブ境界にせず、独立した境界として並べる。
  # type: :strict — 外部ライブラリも含め、依存を一切継承しない。
  # deps に identity / archiving が無いのが要点。
  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [ExAws, ExAws.S3],
    exports: [StoredFile]

  alias App.Storage.{S3Gateway, StoredFile}

  @default_expires_in 900

  @doc """
  ファイルを保存する。

  **キーは呼び出し側に決めさせず、ここで組み立てる。**
  呼び出し側が自由に決めると、命名がバラバラになって後で移行できない。
  """
  @spec upload(String.t(), String.t(), binary(), String.t()) ::
          {:ok, StoredFile.t()} | {:error, term()}
  def upload(owner_id, filename, body, content_type \\ "application/octet-stream") do
    key = build_key(owner_id, filename)

    case S3Gateway.put(key, body, content_type) do
      :ok ->
        {:ok, %StoredFile{key: key, size: byte_size(body), content_type: content_type}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec download(String.t()) :: {:ok, binary() | nil} | {:error, term()}
  def download(key), do: S3Gateway.get(key)

  @spec delete(String.t()) :: :ok | {:error, term()}
  def delete(key), do: S3Gateway.delete(key)

  @spec presigned_url(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def presigned_url(key, opts \\ []) do
    S3Gateway.presigned_url(key, Keyword.get(opts, :expires_in, @default_expires_in))
  end

  @doc "疎通確認（ヘルスチェック用）。"
  @spec ping() :: :ok | {:error, term()}
  def ping, do: S3Gateway.ping()

  # uploads/<owner>/<YYYY/MM/DD>/<uuid>_<filename>
  #
  # 日付を挟むのは、S3 のプレフィックス分散とライフサイクルルールのため。
  # UUID を付けるのは同名ファイルの衝突を避けるため。
  defp build_key(owner_id, filename) do
    safe =
      filename
      |> Path.basename()
      |> String.replace(~r/[^\w.\-]/u, "_")

    date = Date.utc_today() |> Calendar.strftime("%Y/%m/%d")

    "uploads/#{owner_id}/#{date}/#{uuid()}_#{safe}"
  end

  # 衝突しないキーが欲しいだけなので、UUID の体裁に拘らず
  # ランダム 16 バイトを 16 進で並べる。
  # このためだけに uuid ライブラリを足さない。
  defp uuid do
    16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)
  end
end
