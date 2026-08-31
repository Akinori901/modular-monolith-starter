defmodule App.Identity.AuditPublisher do
  @moduledoc """
  監査イベントの発行口。

  **archiving Context を直接呼ばない。**
  直接呼ぶと identity が archiving に依存し、
  認証が監査ログの都合に引きずられる（boundary が検知する）。

  代わりにイベントを publish し、archiving 側が購読する。
  これで依存の向きが切れる。

  ## `:telemetry` を選び、`Phoenix.PubSub` を採らなかった理由

  どちらも「発行側が購読側を知らない」形は作れるが、性質が違う。

  | | `Phoenix.PubSub` | `:telemetry` |
  |---|---|---|
  | 配送 | **非同期**（購読プロセスへ send） | **同期**（発行プロセス上で購読関数を実行） |
  | 用途 | プロセス間のメッセージ配送 | 計測・監査の横断フック |
  | 失敗の伝播 | 発行側に返らない | 購読側の例外を発行側で捕まえられる |

  **監査ログを同期で書きたい**のが決め手。
  「誰がいつサインインしたか」は後から復元できないため、
  書けなかったらサインイン自体を失敗させたい（Rails 版と同じ判断）。

  `Phoenix.PubSub` は配送が非同期なので、発行側は「届いたか」を知れない。
  同期性が欲しければ発行側が購読プロセスの応答を待つ必要があり、
  それは結局「呼び出し」に戻ってしまう。

  `:telemetry` は発行側のプロセス上でハンドラを同期実行するため、
  **依存を切ったまま同期の成否を受け取れる**。
  Rails の `ActiveSupport::Notifications` と同じ位置づけで、
  移植としても素直（あちらも同期実行）。

  なお `Phoenix.PubSub` は Endpoint の設定で起動済みなので、
  「本当に非同期でよい通知」（他ノードへの配信など）には使える。
  ここで採らないのは同期性が要るからであって、優劣ではない。
  """

  @sign_in [:app, :identity, :sign_in]
  @sign_in_failure [:app, :identity, :sign_in_failure]

  @doc "イベント名。購読側（archiving）と共有する唯一の接点。"
  def sign_in_event, do: @sign_in
  def sign_in_failure_event, do: @sign_in_failure

  @doc """
  監査ログは同期で書く（サインインの事実は失ってはならない）。

  購読側が例外を投げたらここまで伝播する。呼び出し元はそれを
  「サインイン失敗」として扱ってよい。
  """
  def sign_in(attrs) do
    :telemetry.execute(@sign_in, %{count: 1}, attrs)
  end

  @doc """
  認証失敗は件数が読めないため非同期で書く（購読側が判断する）。

  **失敗の記録で本体を落とさない。** 購読側が落ちても
  401 を返す処理自体は続けたいので、ここで握りつぶす。
  """
  def sign_in_failure(attrs) do
    :telemetry.execute(@sign_in_failure, %{count: 1}, attrs)
  rescue
    error ->
      require Logger
      # レスポンスには出さないが、原因はログに残す
      Logger.error("監査ログの発行に失敗: #{Exception.message(error)}")
      :ok
  end
end
