defmodule App.Identity.SignIn do
  @moduledoc """
  サインインの手順。

  **このモジュールの役割は「手順の組み立て」だけ。**
  ビジネスルール（サインイン可否の判定など）はスキーマが持つ。
  ここに `if` でルールを書き始めたら、スキーマが貧血症になっている合図。

  Controller に全部書くと、同じ手順を Task や mix タスクから
  呼びたくなったときに再利用できない。この層はそのためにある。
  """

  require Logger

  alias App.Identity.{AuditPublisher, CognitoGateway, User}
  alias App.Repo

  @doc """
  サインインする。

  戻り値は `{:ok, %{tokens: tokens, user: user}}` か
  `{:error, {:authentication_failed, message}}`。
  """
  def call(email, password, meta \\ %{}) do
    with {:ok, tokens} <- CognitoGateway.sign_in(email, password),
         # 検証済みトークンから本人を特定する（Cognito が正）
         {:ok, identity} <- CognitoGateway.verify_access_token(tokens.access_token),
         # ローカル側のユーザーを解決する（初回サインインなら作る）。
         # Cognito が正で、ローカルはプロフィールの保持のみを担う。
         {:ok, user} <- resolve_user(identity.subject, email),
         # 無効化されたアカウントは、Cognito 側が通しても拒否する。
         # 判定規則はスキーマが持つ。ここでは呼ぶだけ。
         :ok <- ensure_can_sign_in(user, email, meta) do
      # 監査ログは**同期**で残す。
      # 「誰がいつサインインしたか」は後から復元できないため、
      # 書けなかったらサインイン自体を失敗させる。
      AuditPublisher.sign_in(%{
        user_id: user.id,
        email: email,
        ip: meta[:ip],
        user_agent: meta[:user_agent]
      })

      {:ok, %{tokens: tokens, user: user}}
    else
      {:error, {:authentication_failed, _} = reason} ->
        record_failure(email, meta, "invalid_credentials")
        {:error, reason}

      {:error, reason} ->
        # 500 を返す場合も、原因はログに残す（レスポンスには出さない）。
        Logger.error("サインインに失敗: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp ensure_can_sign_in(user, email, meta) do
    if User.can_sign_in?(user) do
      :ok
    else
      record_failure(email, meta, "deactivated")
      {:error, {:authentication_failed, "このアカウントは無効化されています"}}
    end
  end

  defp resolve_user(subject, email) do
    case Repo.get(User, subject) do
      nil -> create_user(subject, email)
      user -> {:ok, user}
    end
  end

  defp create_user(subject, email) do
    %User{}
    |> User.changeset(%{
      id: subject,
      email: email,
      display_name: User.default_display_name(email),
      active: true
    })
    |> Repo.insert()
    |> case do
      {:ok, user} ->
        {:ok, user}

      # 同一ユーザーの同時サインインで一意制約に当たることがある。
      # 競合したら「相手が作った行」を読み直せばよい。
      {:error, %Ecto.Changeset{}} ->
        case Repo.get(User, subject) do
          nil -> {:error, :user_creation_failed}
          user -> {:ok, user}
        end
    end
  end

  # 認証失敗も監査対象。**失敗の記録で本体を落とさない**ため、
  # ここは書けなくても握りつぶす（ログには残す）。
  defp record_failure(email, meta, reason) do
    AuditPublisher.sign_in_failure(%{email: email, ip: meta[:ip], reason: reason})
  rescue
    error -> Logger.error("監査ログの記録に失敗: #{Exception.message(error)}")
  end
end
