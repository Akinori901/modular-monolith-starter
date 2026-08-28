# frozen_string_literal: true

module Identity
  # 監査イベントの記録口。
  #
  # **archiving パッケージを直接呼ばない。**
  # 直接呼ぶと identity が archiving に依存し、
  # 認証が監査ログの都合に引きずられる（packwerk が検知する）。
  #
  # 代わりに ActiveSupport::Notifications へ publish し、
  # archiving 側が購読する。これで依存の向きが切れる。
  class AuditRecorder
    SIGN_IN = "identity.sign_in"
    SIGN_IN_FAILURE = "identity.sign_in_failure"

    # 監査ログは同期で書く（サインインの事実は失ってはならない）。
    def record_sign_in(user_id:, email:, ip:, user_agent:)
      ActiveSupport::Notifications.instrument(
        SIGN_IN,
        user_id: user_id, email: email, ip: ip, user_agent: user_agent, synchronous: true
      )
    end

    # 認証失敗は件数が読めないため非同期で書く。
    def record_sign_in_failure(email:, ip:, reason:)
      ActiveSupport::Notifications.instrument(
        SIGN_IN_FAILURE,
        email: email, ip: ip, reason: reason, synchronous: false
      )
    end
  end
end
