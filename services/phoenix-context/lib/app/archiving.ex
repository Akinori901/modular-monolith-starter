defmodule App.Archiving do
  @moduledoc """
  archiving Context の**公開 API**。

  他 Context・Web 層から触ってよいのはこのモジュールと
  `App.Archiving.LogEntry` だけ。
  `App.Archiving.{DynamoGateway, AsyncWriter, IdentityEventSubscriber}` は
  内部実装であり、外から参照するとコンパイル時に落ちる。

  **他 Context に依存しない。** 「誰の」「何の」ログかは
  呼び出し側が値として渡す。identity を参照し始めると
  アーカイブが認証の都合に縛られる。
  """

  # top_level?: true — App のサブ境界にせず、独立した境界として並べる。
  # type: :strict — 外部ライブラリも含め、依存を一切継承しない。
  # deps に identity が無いのが要点（イベントで購読する）。
  use Boundary,
    top_level?: true,
    type: :strict,
    deps: [ExAws, ExAws.Dynamo, Logger],
    exports: [LogEntry]

  alias App.Archiving.{AsyncWriter, DynamoGateway, LogEntry}

  # ログの種別。文字列を直接渡させない（打ち間違いを関数で防ぐ）。
  @audit "audit"
  @access "access"
  @operation "operation"

  def audit, do: @audit
  def access, do: @access
  def operation, do: @operation

  @doc """
  **同期**で書き込む。

  監査ログのように「書けなかったら処理自体を失敗させたい」ものに使う。
  呼び出し側は `{:error, _}` を受け取れる。
  """
  @spec record(String.t(), String.t(), map(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def record(log_type, owner_id, payload, opts \\ []) do
    DynamoGateway.put(log_type, owner_id, payload, occurred_at(opts))
  end

  @doc """
  **非同期**で書き込む。

  アクセスログのように件数が多く、失っても業務が破綻しないものに使う。
  リクエストの応答をブロックしない。常に `:ok` を返す。
  """
  @spec record_later(String.t(), String.t(), map(), keyword()) :: :ok
  def record_later(log_type, owner_id, payload, opts \\ []) do
    AsyncWriter.enqueue(log_type, owner_id, payload, occurred_at(opts))
  end

  @doc "直近のログを新しい順に返す。"
  @spec recent(String.t(), String.t(), keyword()) :: {:ok, [LogEntry.t()]} | {:error, term()}
  def recent(log_type, owner_id, opts \\ []) do
    case DynamoGateway.query(log_type, owner_id, opts) do
      {:ok, items} -> {:ok, Enum.map(items, &to_entry/1)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "疎通確認（ヘルスチェック用）。"
  @spec ping() :: :ok | {:error, term()}
  def ping, do: DynamoGateway.ping()

  @doc "非同期の書き込みが片付くのを待つ（テスト・graceful shutdown 用）。"
  def await_pending(timeout \\ 5_000), do: AsyncWriter.await_all(timeout)

  @doc """
  この Context が必要とする常駐プロセス（非同期書き込みの Task Supervisor）。

  **起動側に内部モジュールを名指しさせないための口。**
  Sidekiq 相当を Oban / SQS へ差し替えても、変わるのはここの中身だけ。
  """
  @spec children() :: [Supervisor.child_spec() | {module(), term()} | module()]
  def children, do: [AsyncWriter]

  @doc """
  他 Context のイベント購読を開始する。

  **購読する側が自分で名乗り出る形にする。**
  起動側が `App.Archiving.IdentityEventSubscriber.attach()` と書くと、
  「誰が誰を購読しているか」が起動コードに散る。
  """
  @spec subscribe!() :: :ok | {:error, term()}
  def subscribe!, do: App.Archiving.IdentityEventSubscriber.attach()

  defp occurred_at(opts) do
    Keyword.get_lazy(opts, :occurred_at, fn -> DateTime.utc_now() end)
  end

  defp to_entry(item) do
    %LogEntry{
      log_type: item["log_type"],
      owner_id: item["owner_id"],
      occurred_at: item["occurred_at"],
      payload: item["payload"] || %{}
    }
  end
end
