# frozen_string_literal: true

require "aws-sdk-cognitoidentityprovider"
require "jwt"
require "net/http"

module Identity
  # Cognito との通信を閉じ込めるゲートウェイ。
  #
  # **AWS SDK と JWT 検証をここだけに置く。**
  # UseCase 側は「認証できること」だけを知り、Cognito を知らない。
  #
  # ローカルでは endpoint に cognito-local を指すだけで同じコードが動く。
  # `if Rails.env.development?` のような分岐をアプリコードに書かない。
  class CognitoGateway
    # 「認証情報が正しくない」系のエラーコード。
    # これらを漏らすと 500 になり、認証エラーが障害として扱われてしまう。
    AUTH_FAILURE_CODES = %w[
      NotAuthorizedException
      UserNotFoundException
      InvalidPasswordException
      InvalidParameterException
      UserNotConfirmedException
    ].freeze

    JWKS_TTL = 12.hours

    Tokens = Struct.new(:access_token, :id_token, :refresh_token, :expires_in, keyword_init: true)
    Identity_ = Struct.new(:subject, :email, keyword_init: true)

    class AuthenticationFailed < StandardError; end

    def initialize(config = Rails.application.config.x.cognito)
      @config = config
      @client = Aws::CognitoIdentityProvider::Client.new(
        **{ region: config.region }.tap { |o|
          o[:endpoint] = config.endpoint if config.endpoint.present?
        }
      )
    end

    # 認証情報を検証しトークンを発行する。
    def sign_in(email:, password:)
      params = { "USERNAME" => email, "PASSWORD" => password }
      params["SECRET_HASH"] = secret_hash(email) if @config.client_secret.present?

      result = @client.initiate_auth(
        client_id: @config.client_id,
        auth_flow: "USER_PASSWORD_AUTH",
        auth_parameters: params
      ).authentication_result

      # MFA 等で追加ステップが要求された場合、authentication_result は nil
      raise AuthenticationFailed, "追加の認証ステップが必要です" if result.nil?

      Tokens.new(
        access_token: result.access_token,
        id_token: result.id_token,
        refresh_token: result.refresh_token.to_s,
        # 実 Cognito では必ず返るが、エミュレータでは省略されることがある。
        # ここで落とすと本番でだけ動く実装になる。
        expires_in: result.expires_in || 3600
      )
    rescue Aws::CognitoIdentityProvider::Errors::ServiceError => e
      # 「ユーザーが存在しない」と「パスワードが違う」を区別して返さないこと。
      # 区別するとアカウント列挙に使われる。
      raise AuthenticationFailed, "メールアドレスまたはパスワードが正しくありません" if auth_failure?(e)

      raise
    end

    # アクセストークンを検証し本人情報を返す。
    def verify_access_token(token)
      claims, = JWT.decode(token, nil, true, algorithms: [ "RS256" ], jwks: jwks, iss: issuer, verify_iss: true)

      # Cognito のアクセストークンには aud が無く client_id が入るため、明示的に照合する。
      raise AuthenticationFailed, "トークンが無効です" unless claims["client_id"] == @config.client_id
      raise AuthenticationFailed, "アクセストークンではありません" unless claims["token_use"] == "access"

      # アクセストークンに email は含まれないことがある
      Identity_.new(subject: claims["sub"], email: claims["email"].to_s)
    rescue JWT::DecodeError
      raise AuthenticationFailed, "トークンが無効です"
    end

    # 疎通確認（ヘルスチェック用）
    def ping
      @client.describe_user_pool(user_pool_id: @config.user_pool_id)
      nil
    end

    private

    def auth_failure?(error)
      AUTH_FAILURE_CODES.include?(error.class.name.split("::").last)
    end

    def issuer
      return @config.issuer_override if @config.issuer_override.present?

      "https://cognito-idp.#{@config.region}.amazonaws.com/#{@config.user_pool_id}"
    end

    # JWKS の取得先と、トークンに刻まれる issuer は必ずしも一致しない。
    # ローカルのエミュレータは自分の公開 URL(localhost) を iss に刻む一方、
    # コンテナからは別ホスト名でしか到達できないため。
    def jwks_url
      @config.jwks_url_override.presence || "#{issuer}/.well-known/jwks.json"
    end

    # JWKS は都度取りに行くとレート制限に当たり、レイテンシも増える。
    def jwks
      Rails.cache.fetch("cognito:jwks:#{@config.user_pool_id}", expires_in: JWKS_TTL) do
        JSON.parse(Net::HTTP.get(URI(jwks_url)), symbolize_names: true)
      end
    end

    def secret_hash(username)
      digest = OpenSSL::HMAC.digest("SHA256", @config.client_secret, username + @config.client_id)
      [ digest ].pack("m0")
    end
  end
end
