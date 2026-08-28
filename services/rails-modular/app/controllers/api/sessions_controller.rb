# frozen_string_literal: true

module Api
  # Controller がやってよいのは 3 つだけ:
  #   1. 入力の検証
  #   2. パッケージの公開 API 呼び出し
  #   3. 応答の組み立て（例外 → HTTP ステータスの変換）
  #
  # **触ってよいのは Identity::Api だけ。**
  # User モデルや SignInUseCase を直接呼ぶと packwerk が落とす。
  class SessionsController < ApplicationController
    def create
      email = params.require(:email)
      password = params.require(:password)

      result = Identity::Api.sign_in(
        email: email,
        password: password,
        ip: request.remote_ip,
        user_agent: request.user_agent
      )

      render json: {
        access_token: result[:tokens].access_token,
        id_token: result[:tokens].id_token,
        refresh_token: result[:tokens].refresh_token,
        expires_in: result[:tokens].expires_in,
        user: result[:user].to_h
      }
    rescue Identity::Api::AuthenticationFailed => e
      # 業務の語彙（認証失敗）を HTTP の語彙（401）へ翻訳するのはここ
      render json: { detail: e.message }, status: :unauthorized
    rescue ActionController::ParameterMissing => e
      render json: { detail: "#{e.param} は必須です" }, status: :bad_request
    end

    def show
      # require_authentication! を通さないと、未認証時に
      # AuthenticationFailed がそのまま漏れて 500 になる（実際に踏んだ）。
      return unless authenticated?

      render json: current_user_view.to_h
    end
  end
end
