defmodule App.AwsHttpClient do
  @moduledoc """
  ExAws の HTTP クライアント。

  ## なぜ ExAws.Request.Hackney をそのまま使わないか

  **ex_aws 2.7.0 の同梱アダプタは hackney 4.x の応答を取りこぼす。**

  同梱アダプタは `:hackney.request/5` の戻り値を
  `{:ok, status, headers, body}` の4要素だけで受けている。
  ところが hackney 4.x は**本文が無い応答**（HEAD リクエストなど）に対して
  `{:ok, status, headers}` の3要素を返す。

  結果、`ExAws.S3.head_bucket/1` が

      ** (CaseClauseError) no case clause matching:
         {:ok, 200, [{"Content-Length", "0"}, ...]}

  で落ちる。ヘルスチェックが head_bucket を使うため、
  **S3 が正常なのに object_storage だけ down と表示される**という形で表面化した
  （実際に踏んだ）。

  ex_aws 2.7.0 は hackney `~> 4.0` を要求しているので、
  「バージョンの取り合わせが悪い」のではなくアダプタ側の取りこぼし。
  依存を古い側へ下げるより、3要素の応答を本文が空として扱う
  クライアントを自前で挿す方が影響範囲が小さい。

  この置き換えは config で行う（config/config.exs の
  `config :ex_aws, http_client: App.AwsHttpClient`）。
  """

  # 全 Context が使う土台なので、独立した境界にして
  # どの Context からも参照できるようにする。
  use Boundary, top_level?: true, type: :strict, deps: [ExAws]

  @behaviour ExAws.Request.HttpClient

  # ExAws の既定に合わせる。
  @default_opts [recv_timeout: 30_000]

  @impl true
  def request(method, url, body \\ "", headers \\ [], http_opts \\ []) do
    opts = http_opts ++ Application.get_env(:ex_aws, :hackney_opts, @default_opts)

    case :hackney.request(method, url, headers, body, opts) do
      {:ok, status, resp_headers, ref} ->
        {:ok, %{status_code: status, headers: resp_headers, body: read_body(ref)}}

      # hackney 4.x は本文が無い応答をこの形で返す（HEAD 等）。
      # 同梱アダプタが取りこぼすのはここ。
      {:ok, status, resp_headers} ->
        {:ok, %{status_code: status, headers: resp_headers, body: ""}}

      {:error, reason} ->
        {:error, %{reason: reason}}
    end
  end

  # hackney は body として「本文そのもの」か「参照」のどちらかを返す。
  defp read_body(ref) when is_reference(ref) do
    case :hackney.body(ref) do
      {:ok, body} -> body
      _ -> ""
    end
  end

  defp read_body(body) when is_binary(body), do: body
  defp read_body(_), do: ""
end
