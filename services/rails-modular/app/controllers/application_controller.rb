# frozen_string_literal: true

class ApplicationController < ActionController::API
  # 認証は Cognito の JWT をパッケージ側で検証する。
  # Rails の session / devise は使わない（Lambda でステートレスに動かすため）。

  private

  def current_user_view
    @current_user_view ||= begin
      token = bearer_token
      raise Identity::Api::AuthenticationFailed, "Authorization ヘッダがありません" if token.nil?

      Identity::Api.current_user(token)
    end
  end

  # before_action 用。認証に失敗したら 401 を返して処理を止める。
  def require_authentication! = authenticated?

  # 認証済みなら true。失敗時は 401 を描画して false を返す。
  #
  # **例外をここで受け止めきること。** 漏らすと 500 になり、
  # 認証エラーが障害として扱われてしまう。
  def authenticated?
    current_user_view
    true
  rescue Identity::Api::AuthenticationFailed => e
    render json: { detail: e.message }, status: :unauthorized
    false
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    return nil unless header.start_with?("Bearer ")

    header.delete_prefix("Bearer ").strip.presence
  end
end
