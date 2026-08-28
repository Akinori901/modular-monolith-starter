# frozen_string_literal: true

module Archiving
  # archiving パッケージの**公開 API**。
  #
  # DynamoGateway / ArchiveLogJob は内部実装であり、
  # 外から参照すると packwerk が落とす。
  class Api
    Error = DynamoGateway::ArchiveError

    # ログの種別。文字列を直接渡させない（打ち間違いを型で防ぐ）。
    AUDIT = "audit"
    ACCESS = "access"
    OPERATION = "operation"

    LogEntry = Struct.new(:log_type, :owner_id, :occurred_at, :payload, keyword_init: true) do
      def to_h
        { log_type: log_type, owner_id: owner_id, occurred_at: occurred_at, payload: payload }
      end
    end

    class << self
      # **同期**で書き込む。
      #
      # 監査ログのように「書けなかったら処理自体を失敗させたい」ものに使う。
      # 呼び出し側は例外を受け取れる。
      def record!(log_type:, owner_id:, payload:, occurred_at: Time.current)
        DynamoGateway.new.put(
          log_type: log_type, owner_id: owner_id,
          payload: payload, occurred_at: occurred_at
        )
      end

      # **非同期**でキューに積む。
      #
      # アクセスログのように件数が多く、失っても業務が破綻しないものに使う。
      # リクエストの応答をブロックしない。
      def record_later(log_type:, owner_id:, payload:, occurred_at: Time.current)
        ArchiveLogJob.perform_later(
          log_type: log_type, owner_id: owner_id,
          payload: payload, occurred_at: occurred_at.utc.iso8601(6)
        )
      end

      # 直近のログを新しい順に返す。
      def recent(log_type:, owner_id:, limit: 50, since: nil)
        DynamoGateway.new.query(
          log_type: log_type, owner_id: owner_id, limit: limit, since: since
        ).map { |item| to_entry(item) }
      end

      def ping = DynamoGateway.new.ping

      private

      def to_entry(item)
        LogEntry.new(
          log_type: item["log_type"], owner_id: item["owner_id"],
          occurred_at: item["occurred_at"], payload: item["payload"]
        )
      end
    end
  end
end
