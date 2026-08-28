# frozen_string_literal: true

module Archiving
  # ログを非同期で DynamoDB へ書き込む Job。
  #
  # **非同期にしてよいのは「失っても業務が破綻しないログ」だけ。**
  # 監査ログ（誰がサインインしたか）は同期で書く。Api を参照。
  class ArchiveLogJob < ApplicationJob
    queue_as :archiving

    # DynamoDB のスロットリングは時間を置けば回復するため、リトライする。
    retry_on Archiving::DynamoGateway::ArchiveError, wait: :polynomially_longer, attempts: 5

    # 引数が壊れている場合は何度やっても通らないので捨てる（無限リトライを避ける）。
    discard_on ArgumentError

    def perform(log_type:, owner_id:, payload:, occurred_at: nil)
      DynamoGateway.new.put(
        log_type: log_type,
        owner_id: owner_id,
        payload: payload,
        occurred_at: occurred_at ? Time.zone.parse(occurred_at) : Time.current
      )
    end
  end
end
