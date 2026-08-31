defmodule App.Archiving.IdentityEventSubscriber do
  @moduledoc """
  identity Context のイベントを購読してアーカイブする。

  **依存の向きがここで反転している点が重要。**
  identity が archiving を呼ぶのではなく、archiving が identity の
  イベントを聞きに行く。こうすると:

    - identity は archiving を知らない（`deps` に archiving を書かずに済む）
    - アーカイブを止めても認証は動く
    - 購読者を増やしても identity は変わらない

  **イベント名（アトムのリスト）だけが両者の接点**になる。

  ## なぜ identity のモジュールを参照していないか

  イベント名は `App.Identity.AuditPublisher.sign_in_event()` を
  呼べば取れるが、それをすると archiving が identity に依存する
  （boundary が落とす）。接点は文字列・アトムに留める。

  archiving Context の内部実装。Context の外からは見えない。
  """

  require Logger

  alias App.Archiving

  # identity 側と同じ値を、依存を作らずに持つ。
  # 片方だけ変えるとイベントが届かなくなるため、テストで両者の一致を見る。
  @sign_in [:app, :identity, :sign_in]
  @sign_in_failure [:app, :identity, :sign_in_failure]

  @handler_id "archiving-identity-events"

  @doc """
  購読しているイベント名。

  依存を切っている代償として、イベント名は identity 側と
  **別々に**書かれている。片方だけ変えると黙って届かなくなるため、
  テストで両者の一致を突き合わせられるように公開する。
  """
  def subscribed_events, do: [@sign_in, @sign_in_failure]

  @doc "起動時に1度だけ呼ぶ。"
  def attach do
    :telemetry.attach_many(
      @handler_id,
      subscribed_events(),
      &__MODULE__.handle_event/4,
      nil
    )
  end

  def detach, do: :telemetry.detach(@handler_id)

  @doc false
  # サインイン成功は**同期**（監査ログ。失ってはならない）。
  #
  # :telemetry のハンドラは発行プロセス上で同期実行されるため、
  # ここで例外を投げれば identity 側のサインインごと失敗する。
  # それが監査ログに求める挙動（Rails 版と同じ判断）。
  def handle_event(@sign_in, _measurements, meta, _config) do
    case Archiving.record(Archiving.audit(), meta[:user_id], %{
           event: "sign_in",
           email: meta[:email],
           ip: meta[:ip],
           user_agent: meta[:user_agent]
         }) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        # 同期で書けなかった＝サインインを成立させてはいけない
        raise "監査ログの書き込みに失敗しました: #{inspect(reason)}"
    end
  end

  # サインイン失敗は**非同期**（件数が読めない。攻撃時に大量発生する）
  def handle_event(@sign_in_failure, _measurements, meta, _config) do
    Archiving.record_later(
      Archiving.audit(),
      # 認証前なので user_id が無い。IP を所有者キーにする。
      meta[:ip] || "unknown",
      %{event: "sign_in_failure", email: meta[:email], reason: meta[:reason]}
    )

    :ok
  end
end
