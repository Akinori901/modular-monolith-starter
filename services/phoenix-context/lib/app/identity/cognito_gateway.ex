defmodule App.Identity.CognitoGateway do
  @moduledoc """
  Cognito との通信を閉じ込めるゲートウェイ。

  **AWS の呼び出しと JWT 検証をここだけに置く。**
  Context 本体は「認証できること」だけを知り、Cognito を知らない。

  ローカルでは endpoint に cognito-local を指すだけで同じコードが動く。
  `if Mix.env() == :dev` のような分岐をアプリコードに書かない。

  ## ex_aws に Cognito IdP のパッケージが無い件

  S3 / DynamoDB と違い、**Cognito Identity Provider には維持されている
  ex_aws パッケージが存在しない**（`ex_aws_cognito_identity` は
  Federated Identities という別サービス、`cognitex` は 0.1.0 で更新停止）。

  Cognito IdP は JSON プロトコル（`X-Amz-Target` ヘッダで操作を指定する）
  なので、必要な2操作だけ `ExAws.Operation.JSON` を直接組み立てる。
  署名・リトライ・エンドポイント解決は ex_aws がそのまま面倒を見る。
  """

  alias App.Identity.JwksCache
  alias App.Identity.Tokens

  # 「認証情報が正しくない」系のエラーコード。
  # これらを漏らすと 500 になり、認証エラーが障害として扱われてしまう。
  #
  # **cognito-local は例外を型付きで返さない**ため、
  # レスポンス本文の __type 文字列で判定する。
  @auth_failure_codes ~w[
    NotAuthorizedException
    UserNotFoundException
    InvalidPasswordException
    InvalidParameterException
    UserNotConfirmedException
  ]

  # 実 Cognito のアクセストークンは 1 時間。
  # エミュレータが ExpiresIn を返さないときの既定値に使う。
  @default_expires_in 3600

  @service :"cognito-idp"

  @doc """
  認証情報を検証しトークンを発行する。

  「ユーザーが存在しない」と「パスワードが違う」を区別して返さないこと。
  区別するとアカウント列挙に使われる。
  """
  @spec sign_in(String.t(), String.t()) :: {:ok, Tokens.t()} | {:error, term()}
  def sign_in(email, password) do
    config = config()

    auth_parameters =
      %{"USERNAME" => email, "PASSWORD" => password}
      |> put_secret_hash(email, config)

    request("InitiateAuth", %{
      "ClientId" => config[:client_id],
      "AuthFlow" => "USER_PASSWORD_AUTH",
      "AuthParameters" => auth_parameters
    })
    |> case do
      {:ok, %{"AuthenticationResult" => result}} ->
        {:ok, to_tokens(result)}

      # MFA 等で追加ステップが要求された場合 AuthenticationResult が返らない
      {:ok, %{"ChallengeName" => _}} ->
        {:error, {:authentication_failed, "追加の認証ステップが必要です"}}

      {:ok, _other} ->
        {:error, {:authentication_failed, "追加の認証ステップが必要です"}}

      {:error, reason} ->
        classify(reason)
    end
  end

  @doc """
  アクセストークンを検証し `{:ok, %{subject: sub, email: email}}` を返す。
  """
  @spec verify_access_token(String.t()) :: {:ok, map()} | {:error, term()}
  def verify_access_token(token) when is_binary(token) and token != "" do
    config = config()

    with {:ok, jwks} <- jwks(config),
         {:ok, claims} <- verify_signature(token, jwks),
         :ok <- verify_claims(claims, config) do
      {:ok, %{subject: claims["sub"], email: claims["email"] || ""}}
    else
      {:error, {:authentication_failed, _} = reason} -> {:error, reason}
      _ -> {:error, {:authentication_failed, "トークンが無効です"}}
    end
  end

  def verify_access_token(_), do: {:error, {:authentication_failed, "トークンが無効です"}}

  @doc "疎通確認（ヘルスチェック用）。"
  @spec ping() :: :ok | {:error, term()}
  def ping do
    case request("DescribeUserPool", %{"UserPoolId" => config()[:user_pool_id]}) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # ── 内部 ───────────────────────────────────────────────

  defp to_tokens(result) do
    %Tokens{
      access_token: result["AccessToken"],
      id_token: result["IdToken"],
      refresh_token: result["RefreshToken"] || "",
      # 実 Cognito では必ず返るが、エミュレータでは省略されることがある。
      # ここで落とすと本番でだけ動く実装になる。
      expires_in: result["ExpiresIn"] || @default_expires_in
    }
  end

  # cognito-local は例外を型付きで返さない。
  # HTTP のボディに入る __type の文字列で判定する。
  defp classify({:http_error, _status, %{body: body}}) do
    type =
      case Jason.decode(body) do
        {:ok, %{"__type" => type}} -> type |> String.split("#") |> List.last()
        _ -> nil
      end

    if type in @auth_failure_codes do
      {:error, {:authentication_failed, "メールアドレスまたはパスワードが正しくありません"}}
    else
      {:error, {:cognito_error, body}}
    end
  end

  defp classify(reason), do: {:error, {:cognito_error, reason}}

  defp put_secret_hash(params, _email, %{client_secret: nil}), do: params
  defp put_secret_hash(params, _email, %{client_secret: ""}), do: params

  defp put_secret_hash(params, email, config) do
    hash =
      :hmac
      |> :crypto.mac(:sha256, config[:client_secret], email <> config[:client_id])
      |> Base.encode64()

    Map.put(params, "SECRET_HASH", hash)
  end

  defp request(operation, data) do
    %ExAws.Operation.JSON{
      http_method: :post,
      service: @service,
      headers: [
        {"x-amz-target", "AWSCognitoIdentityProviderService.#{operation}"},
        {"content-type", "application/x-amz-json-1.1"}
      ],
      data: data
    }
    |> ExAws.request()
  end

  # ── JWT 検証 ──────────────────────────────────────────

  defp verify_signature(token, jwks) do
    with {:ok, %{"kid" => kid}} <- peek_header(token),
         %{} = jwk <- find_key(jwks, kid) do
      signer = Joken.Signer.create("RS256", jwk)

      case Joken.verify(token, signer) do
        {:ok, claims} -> {:ok, claims}
        {:error, _} -> {:error, {:authentication_failed, "トークンが無効です"}}
      end
    else
      _ -> {:error, {:authentication_failed, "トークンが無効です"}}
    end
  end

  defp peek_header(token) do
    Joken.peek_header(token)
  rescue
    _ -> :error
  end

  defp find_key(%{"keys" => keys}, kid), do: Enum.find(keys, &(&1["kid"] == kid))
  defp find_key(_, _), do: nil

  defp verify_claims(claims, config) do
    cond do
      # Cognito のアクセストークンには aud が無く client_id が入るため、明示的に照合する
      claims["client_id"] != config[:client_id] ->
        {:error, {:authentication_failed, "トークンが無効です"}}

      claims["token_use"] != "access" ->
        {:error, {:authentication_failed, "アクセストークンではありません"}}

      claims["iss"] != issuer(config) ->
        {:error, {:authentication_failed, "トークンが無効です"}}

      expired?(claims["exp"]) ->
        {:error, {:authentication_failed, "トークンの有効期限が切れています"}}

      true ->
        :ok
    end
  end

  defp expired?(nil), do: true
  defp expired?(exp) when is_integer(exp), do: exp <= System.system_time(:second)
  defp expired?(_), do: true

  defp issuer(config) do
    config[:issuer_override] ||
      "https://cognito-idp.#{config[:region]}.amazonaws.com/#{config[:user_pool_id]}"
  end

  # JWKS の取得先と、トークンに刻まれる issuer は必ずしも一致しない。
  # ローカルのエミュレータは自分の公開 URL(localhost) を iss に刻む一方、
  # コンテナからは別ホスト名でしか到達できないため。
  defp jwks_url(config) do
    config[:jwks_url_override] || "#{issuer(config)}/.well-known/jwks.json"
  end

  # JWKS は都度取りに行くとレート制限に当たり、レイテンシも増える。
  # ETS のキャッシュ越しに取る。
  defp jwks(config) do
    JwksCache.fetch(jwks_url(config))
  end

  defp config do
    Application.fetch_env!(:app, :cognito) |> Map.new()
  end
end
