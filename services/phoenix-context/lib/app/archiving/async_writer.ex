defmodule App.Archiving.AsyncWriter do
  @moduledoc """
  ログを非同期で DynamoDB へ書き込む。

  **非同期にしてよいのは「失っても業務が破綻しないログ」だけ。**
  監査ログ（誰がサインインしたか）は同期で書く。`App.Archiving` を参照。

  ## Sidekiq 相当のものを入れなかった理由

  Rails 版は Sidekiq + Redis でワーカープロセスを分けている。
  Ruby は「リクエストを処理するプロセスで重い仕事をさせられない」ため、
  外部キューと常駐ワーカーがほぼ必須になる。

  BEAM は軽量プロセスが標準機能で、Supervisor による
  監督・再起動も言語処理系の側にある。**アプリと同じ VM 上で
  監督付きの非同期処理を回せる**ので、まず `Task.Supervisor` を採る。

  これで足りなくなるのは、次のどちらかが要るときだけ:

  - **再起動を跨いだ永続化**（プロセスが落ちたら積んだ仕事も消える）
  - **複数ノードに跨る分配**

  そのときは Oban（DB 永続キュー）や SQS へ差し替える。
  差し替え先はこのモジュールの中だけで済み、
  `App.Archiving` の公開面は変わらない。

  archiving Context の内部実装。Context の外からは見えない。
  """

  require Logger

  alias App.Archiving.DynamoGateway

  @supervisor App.Archiving.TaskSupervisor

  # DynamoDB のスロットリングは時間を置けば回復するため、リトライする。
  @max_attempts 5
  @base_backoff_ms 100

  @doc """
  非同期で書き込む。呼び出しは即座に返る。

  戻り値は `:ok` 固定。**呼び出し元は結果を待たない。**
  待つ必要があるなら、それは非同期にしてよいログではない。
  """
  @spec enqueue(String.t(), String.t(), map(), DateTime.t()) :: :ok
  def enqueue(log_type, owner_id, payload, occurred_at) do
    Task.Supervisor.start_child(@supervisor, fn ->
      write_with_retry(log_type, owner_id, payload, occurred_at, 1)
    end)

    :ok
  end

  @doc "テストから完了を待つためのフック。本番の経路では使わない。"
  def await_all(timeout \\ 5_000) do
    @supervisor
    |> Task.Supervisor.children()
    |> Enum.each(fn pid ->
      ref = Process.monitor(pid)

      receive do
        {:DOWN, ^ref, :process, ^pid, _} -> :ok
      after
        timeout -> Process.demonitor(ref, [:flush])
      end
    end)
  end

  defp write_with_retry(log_type, owner_id, payload, occurred_at, attempt) do
    case DynamoGateway.put(log_type, owner_id, payload, occurred_at) do
      {:ok, sk} ->
        {:ok, sk}

      {:error, _reason} when attempt < @max_attempts ->
        # 指数バックオフ。スロットリングに同じ間隔で殴り返さない。
        Process.sleep(@base_backoff_ms * Integer.pow(2, attempt - 1))
        write_with_retry(log_type, owner_id, payload, occurred_at, attempt + 1)

      {:error, reason} ->
        # 諦めるが、**原因はログに残す**。
        # 非同期ログの取りこぼしを黙って捨てると、
        # 「ログが無い」のか「書けなかった」のか判別できなくなる。
        Logger.error(
          "ログのアーカイブに失敗（#{@max_attempts}回試行）: " <>
            "log_type=#{log_type} owner_id=#{owner_id} reason=#{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  @doc "Supervisor の子仕様。App.Application から起動する。"
  def child_spec(_opts) do
    Task.Supervisor.child_spec(name: @supervisor)
  end
end
