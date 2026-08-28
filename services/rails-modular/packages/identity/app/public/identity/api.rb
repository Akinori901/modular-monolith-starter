# frozen_string_literal: true

module Identity
  # identity パッケージの**公開 API**。
  #
  # 他パッケージ・Controller から触ってよいのはこのクラスだけ。
  # packages/identity/app/{models,services,gateways,use_cases}/ は
  # すべて内部実装であり、外から参照すると packwerk が落とす
  # （enforce_privacy: true）。
  #
  # 公開面を1枚に絞ることで、内部をいくら作り替えても
  # 呼び出し側が壊れない状態を保つ。
  class Api
    AuthenticationFailed = CognitoGateway::AuthenticationFailed

    # 公開する形。ActiveRecord をそのまま返さない。
    # 返すと呼び出し側がテーブル構造に依存してしまう。
    UserView = Struct.new(:id, :email, :display_name, :active, keyword_init: true) do
      def to_h = { user_id: id, email: email, display_name: display_name, is_active: active }
    end

    class << self
      # サインインする。
      # @raise [AuthenticationFailed]
      def sign_in(email:, password:, ip: nil, user_agent: nil)
        result = SignInUseCase.new.call(
          email: email, password: password, ip: ip, user_agent: user_agent
        )
        { tokens: result.tokens, user: to_view(result.user) }
      end

      # アクセストークンから現在のユーザーを返す。
      # @raise [AuthenticationFailed]
      def current_user(access_token)
        identity = CognitoGateway.new.verify_access_token(access_token)
        user = User.find_by(id: identity.subject)
        raise AuthenticationFailed, "ユーザーが見つかりません" if user.nil?

        to_view(user)
      end

      # 疎通確認（ヘルスチェック用）
      def ping = CognitoGateway.new.ping

      private

      def to_view(user)
        UserView.new(
          id: user.id, email: user.email,
          display_name: user.display_name, active: user.can_sign_in?
        )
      end
    end
  end
end
