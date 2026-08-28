# frozen_string_literal: true

# ActiveRecord モデル。
#
# **Rails ウェイに逆らわない。** Repository 層で包んだりしない。
# 代わりに「このモデルを誰が触ってよいか」を packwerk が制御する。
#
# このクラスは identity パッケージの内部実装であり、
# public/ に出していないため他パッケージからは参照できない
# （enforce_privacy: true）。外へ見せるのは Identity::Api だけ。
class User < ApplicationRecord
  # Cognito の sub を主キーにする（採番を Cognito に委ねる）
  self.primary_key = :id

  validates :email, presence: true, uniqueness: true
  validates :display_name, presence: true, length: { maximum: 50 }

  scope :active, -> { where(active: true) }

  # サインイン可能かを判定する（ビジネスルール）。
  #
  # この判定を Controller や UseCase の if で書かないこと。
  # モデルに置かないと、同じ判定が各所へ散らばる。
  def can_sign_in? = active?

  def deactivate! = update!(active: false)
end
