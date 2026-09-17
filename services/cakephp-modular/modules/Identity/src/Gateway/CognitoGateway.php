<?php
declare(strict_types=1);

namespace Identity\Gateway;

use Aws\CognitoIdentityProvider\CognitoIdentityProviderClient;
use Aws\Exception\AwsException;
use Cake\Cache\Cache;
use Cake\Core\Configure;
use Firebase\JWT\JWK;
use Firebase\JWT\JWT;
use Identity\Exception\AuthenticationFailedException;

/**
 * Cognito との通信を閉じ込めるゲートウェイ。
 *
 * **AWS SDK と JWT 検証をここだけに置く。**
 * UseCase 側は「認証できること」だけを知り、Cognito を知らない。
 *
 * ローカルでは endpoint に cognito-local を指すだけで同じコードが動く。
 * `if (env('DEBUG'))` のような分岐をアプリコードに書かない。
 */
class CognitoGateway
{
    /**
     * 「認証情報が正しくない」系のエラーコード。
     *
     * これらを漏らすと 500 になり、認証エラーが障害として扱われてしまう。
     * **型ではなくコード文字列で判定する。** エミュレータや一部経路では
     * 型付きの例外にならず、instanceof では取りこぼす。
     */
    private const AUTH_FAILURE_CODES = [
        'NotAuthorizedException',
        'UserNotFoundException',
        'InvalidPasswordException',
        'InvalidParameterException',
        'UserNotConfirmedException',
    ];

    // JWKS の TTL はここではなく config/bootstrap.php の Cache 設定
    // （'cognito' の duration）が持つ。同じ値を 2 か所に置くと必ずずれる。

    private CognitoIdentityProviderClient $client;

    /** @var array<string, mixed> */
    private array $config;

    public function __construct(?CognitoIdentityProviderClient $client = null)
    {
        $this->config = (array)Configure::read('Cognito');

        $args = [
            'version' => 'latest',
            'region' => $this->config['region'],
        ];
        if (!empty($this->config['endpoint'])) {
            $args['endpoint'] = $this->config['endpoint'];
        }

        $this->client = $client ?? new CognitoIdentityProviderClient($args);
    }

    /**
     * 認証情報を検証しトークンを発行する。
     *
     * @return array{access_token:string,id_token:string,refresh_token:string,expires_in:int}
     * @throws \Identity\Exception\AuthenticationFailedException
     */
    public function signIn(string $email, string $password): array
    {
        $params = ['USERNAME' => $email, 'PASSWORD' => $password];
        if (!empty($this->config['client_secret'])) {
            $params['SECRET_HASH'] = $this->secretHash($email);
        }

        try {
            $response = $this->client->initiateAuth([
                'ClientId' => $this->config['client_id'],
                'AuthFlow' => 'USER_PASSWORD_AUTH',
                'AuthParameters' => $params,
            ]);
        } catch (AwsException $e) {
            // 「ユーザーが存在しない」と「パスワードが違う」を区別して返さないこと。
            // 区別するとアカウント列挙に使われる。
            if (in_array($e->getAwsErrorCode(), self::AUTH_FAILURE_CODES, true)) {
                throw new AuthenticationFailedException(
                    'メールアドレスまたはパスワードが正しくありません'
                );
            }
            throw $e;
        }

        $result = $response['AuthenticationResult'] ?? null;
        if ($result === null) {
            // MFA 等で追加ステップが要求された場合
            throw new AuthenticationFailedException('追加の認証ステップが必要です');
        }

        return [
            'access_token' => $result['AccessToken'],
            'id_token' => $result['IdToken'],
            'refresh_token' => $result['RefreshToken'] ?? '',
            // 実 Cognito では必ず返るが、エミュレータでは省略されることがある。
            // ここで落とすと本番でだけ動く実装になる。
            'expires_in' => (int)($result['ExpiresIn'] ?? 3600),
        ];
    }

    /**
     * アクセストークンを検証し本人情報を返す。
     *
     * @return array{subject:string,email:string}
     * @throws \Identity\Exception\AuthenticationFailedException
     */
    public function verifyAccessToken(string $token): array
    {
        try {
            $claims = (array)JWT::decode($token, JWK::parseKeySet($this->jwks()));
        } catch (\Throwable $e) {
            throw new AuthenticationFailedException('トークンが無効です', 0, $e);
        }

        if (($claims['iss'] ?? null) !== $this->issuer()) {
            throw new AuthenticationFailedException('発行元が一致しません');
        }
        if (($claims['token_use'] ?? null) !== 'access') {
            throw new AuthenticationFailedException('アクセストークンではありません');
        }
        // Cognito のアクセストークンには aud が無く client_id が入る
        if (($claims['client_id'] ?? null) !== $this->config['client_id']) {
            throw new AuthenticationFailedException('発行先クライアントが一致しません');
        }

        return [
            'subject' => (string)$claims['sub'],
            // アクセストークンに email は含まれないことがある
            'email' => (string)($claims['email'] ?? ''),
        ];
    }

    /** 疎通確認（ヘルスチェック用） */
    public function ping(): void
    {
        $this->client->describeUserPool(['UserPoolId' => $this->config['user_pool_id']]);
    }

    private function issuer(): string
    {
        if (!empty($this->config['issuer_override'])) {
            return $this->config['issuer_override'];
        }

        return sprintf(
            'https://cognito-idp.%s.amazonaws.com/%s',
            $this->config['region'],
            $this->config['user_pool_id']
        );
    }

    /**
     * JWKS の取得先と、トークンに刻まれる issuer は必ずしも一致しない。
     * ローカルのエミュレータは自分の公開 URL(localhost) を iss に刻む一方、
     * コンテナからは別ホスト名でしか到達できないため。
     */
    private function jwksUrl(): string
    {
        return !empty($this->config['jwks_url_override'])
            ? $this->config['jwks_url_override']
            : $this->issuer() . '/.well-known/jwks.json';
    }

    /**
     * JWKS は都度取りに行くとレート制限に当たり、レイテンシも増える。
     *
     * @return array<string, mixed>
     */
    private function jwks(): array
    {
        $key = 'cognito_jwks_' . md5((string)$this->config['user_pool_id']);

        return Cache::remember($key, function (): array {
            $body = file_get_contents($this->jwksUrl());
            if ($body === false) {
                throw new AuthenticationFailedException('JWKS の取得に失敗しました');
            }

            return json_decode($body, true, 512, JSON_THROW_ON_ERROR);
        }, 'cognito');
    }

    private function secretHash(string $username): string
    {
        return base64_encode(hash_hmac(
            'sha256',
            $username . $this->config['client_id'],
            (string)$this->config['client_secret'],
            true
        ));
    }
}
