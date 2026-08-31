# frozen_string_literal: true

module Archiving
  # identity パッケージのイベントを購読してアーカイブする。
  #
  # **依存の向きがここで反転している点が重要。**
  # identity が archiving を呼ぶのではなく、archiving が identity の
  # イベントを聞きに行く。こうすると:
  #
  #   - identity は archiving を知らない（package.yml の dependencies が空のまま）
  #   - アーカイブを止めても認証は動く
  #   - 購読者を増やしても identity は変わらない
  #
  # イベント名の文字列だけが両者の接点になる。
  class IdentityEventSubscriber
    SIGN_IN = "identity.sign_in"
    SIGN_IN_FAILURE = "identity.sign_in_failure"

    def self.subscribe!
      new.subscribe!
    end

    def subscribe!
      ActiveSupport::Notifications.subscribe(SIGN_IN) do |*args|
        handle_sign_in(ActiveSupport::Notifications::Event.new(*args).payload)
      end

      ActiveSupport::Notifications.subscribe(SIGN_IN_FAILURE) do |*args|
        handle_sign_in_failure(ActiveSupport::Notifications::Event.new(*args).payload)
      end
    end

    private

    # サインイン成功は**同期**（監査ログ。失ってはならない）
    def handle_sign_in(payload)
      Archiving::Api.record!(
        log_type: Archiving::Api::AUDIT,
        owner_id: payload[:user_id],
        payload: {
          event: "sign_in",
          email: payload[:email],
          ip: payload[:ip],
          user_agent: payload[:user_agent]
        }
      )
    end

    # サインイン失敗は**非同期**（件数が読めない。攻撃時に大量発生する）
    def handle_sign_in_failure(payload)
      Archiving::Api.record_later(
        log_type: Archiving::Api::AUDIT,
        # 認証前なので user_id が無い。IP を所有者キーにする。
        owner_id: payload[:ip].presence || "unknown",
        payload: {
          event: "sign_in_failure",
          email: payload[:email],
          reason: payload[:reason]
        }
      )
    end
  end
end
