# frozen_string_literal: true

require "rails_helper"

# **モデルにビジネスルールを持たせていることのテスト。**
# 「サインインできるか」は User の責務であり、UseCase の if ではない。
RSpec.describe User do
  subject(:user) do
    described_class.new(id: "sub-1", email: "taro@example.com", display_name: "taro", active: true)
  end

  it "有効なユーザーはサインインできる" do
    expect(user).to be_can_sign_in
  end

  it "無効化するとサインインできなくなる" do
    user.active = false
    expect(user).not_to be_can_sign_in
  end

  it "表示名は50文字まで" do
    user.display_name = "あ" * 51
    expect(user).not_to be_valid
  end

  it "メールアドレスは必須" do
    user.email = nil
    expect(user).not_to be_valid
  end
end
