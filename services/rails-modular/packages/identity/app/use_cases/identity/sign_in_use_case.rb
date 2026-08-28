# frozen_string_literal: true

module Identity
  # サインインのユースケース。
  #
  # **UseCase の役割は「手順の組み立て」だけ。**
  # ビジネスルール（サインイン可否の判定など）はモデルが持つ。
  # ここに if でルールを書き始めたら、モデルが貧血症になっている合図。
  #
  # Rails の Controller に全部書くと、同じ手順を Job や rake から
  # 呼びたくなったときに再利用できない。UseCase はそのための層。
  class SignInUseCase
    Result = Struct.new(:tokens, :user, keyword_init: true)

    def initialize(cognito: CognitoGateway.new, audit: AuditRecorder.new)
      @cognito = cognito
      @audit = audit
    end

    # @raise [CognitoGateway::AuthenticationFailed]
    def call(email:, password:, ip: nil, user_agent: nil)
      # 1. 認証基盤（Cognito）で認証する
      tokens = @cognito.sign_in(email: email, password: password)

      # 2. 検証済みトークンから本人を特定する
      identity = @cognito.verify_access_token(tokens.access_token)

      # 3. ローカル側のユーザーを解決する（初回サインインなら作る）
      #    Cognito が正で、ローカルはプロフィールの保持のみを担う。
      user = resolve_user(identity.subject, email)

      # 4. 無効化されたアカウントは、Cognito 側が通しても拒否する。
      #    判定規則はモデルが持つ。ここでは呼ぶだけ。
      unless user.can_sign_in?
        record_failure(email: email, ip: ip, reason: "deactivated")
        raise CognitoGateway::AuthenticationFailed, "このアカウントは無効化されています"
      end

      # 5. 監査ログは**同期**で残す。
      #    「誰がいつサインインしたか」は後から復元できないため、
      #    書けなかったらサインイン自体を失敗させる。
      @audit.record_sign_in(user_id: user.id, email: email, ip: ip, user_agent: user_agent)

      Result.new(tokens: tokens, user: user)
    rescue CognitoGateway::AuthenticationFailed
      record_failure(email: email, ip: ip, reason: "invalid_credentials")
      raise
    end

    private

    def resolve_user(subject, email)
      User.find_by(id: subject) || User.create!(
        id: subject,
        email: email,
        display_name: email.split("@").first,
        active: true
      )
    end

    # 認証失敗も監査対象。**失敗の記録で本体を落とさない**ため、
    # ここは書けなくても握りつぶす（ログには残す）。
    def record_failure(email:, ip:, reason:)
      @audit.record_sign_in_failure(email: email, ip: ip, reason: reason)
    rescue StandardError => e
      Rails.logger.error("監査ログの記録に失敗: #{e.message}")
    end
  end
end
