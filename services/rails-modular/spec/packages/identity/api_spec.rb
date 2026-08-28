# frozen_string_literal: true

require "rails_helper"

# **公開 API が ActiveRecord を返さないことのテスト。**
# 返してしまうと、呼び出し側がテーブル構造に依存する。
RSpec.describe Identity::Api do
  describe "UserView" do
    it "ActiveRecord ではなく値の構造体を返す" do
      view = described_class::UserView.new(
        id: "sub-1", email: "taro@example.com", display_name: "taro", active: true
      )

      expect(view).not_to be_a(ActiveRecord::Base)
      expect(view.to_h).to eq(
        user_id: "sub-1", email: "taro@example.com",
        display_name: "taro", is_active: true
      )
    end
  end
end
