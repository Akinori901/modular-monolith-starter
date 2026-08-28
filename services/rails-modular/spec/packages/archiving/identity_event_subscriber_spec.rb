# frozen_string_literal: true

require "rails_helper"

# **パッケージ間がイベントで繋がっていることのテスト。**
# identity は archiving を知らないまま、archiving 側が購読する。
RSpec.describe Archiving::IdentityEventSubscriber do
  it "サインイン成功は同期で記録する（監査ログは失ってはならない）" do
    expect(Archiving::Api).to receive(:record!).with(
      hash_including(log_type: Archiving::Api::AUDIT, owner_id: "sub-1")
    )

    ActiveSupport::Notifications.instrument(
      "identity.sign_in",
      user_id: "sub-1", email: "taro@example.com", ip: "127.0.0.1", user_agent: "test"
    )
  end

  it "サインイン失敗は非同期で記録する（攻撃時に大量発生するため）" do
    expect(Archiving::Api).to receive(:record_later).with(
      hash_including(log_type: Archiving::Api::AUDIT, owner_id: "127.0.0.1")
    )

    ActiveSupport::Notifications.instrument(
      "identity.sign_in_failure",
      email: "nobody@example.com", ip: "127.0.0.1", reason: "invalid_credentials"
    )
  end
end
