<?php
declare(strict_types=1);

namespace App\Controller;

use Cake\Controller\Controller;
use Identity\Exception\AuthenticationFailedException;
use Identity\Public\IdentityApi;

/**
 * API 用の基底コントローラ。
 *
 * 認証は Cognito の JWT をモジュール側で検証する。
 * セッションは使わない（Lambda でステートレスに動かすため）。
 */
class AppController extends Controller
{
    /** @var array<string, mixed>|null */
    private ?array $currentUser = null;

    /**
     * 認証を要求する。未認証なら 401 を返して null を返す。
     *
     * @return array<string, mixed>|null
     */
    protected function requireAuthentication(): ?array
    {
        if ($this->currentUser !== null) {
            return $this->currentUser;
        }

        $header = $this->request->getHeaderLine('Authorization');
        if (!str_starts_with($header, 'Bearer ')) {
            $this->respond(['detail' => 'Authorization ヘッダがありません'], 401);

            return null;
        }

        $token = trim(substr($header, 7));
        if ($token === '') {
            $this->respond(['detail' => 'Authorization ヘッダがありません'], 401);

            return null;
        }

        try {
            $this->currentUser = (new IdentityApi())->currentUser($token);
        } catch (AuthenticationFailedException $e) {
            $this->respond(['detail' => $e->getMessage()], 401);

            return null;
        }

        return $this->currentUser;
    }

    /**
     * JSON で応答する。
     *
     * **autoRender を切ること。** 切らないと CakePHP がテンプレートを
     * 探しに行き、API しか無い本アプリでは "Missing Template" になる
     * （実際に踏んだ）。
     *
     * @param array<string, mixed> $body
     */
    protected function respond(array $body, int $status): void
    {
        $this->autoRender = false;

        $this->response = $this->response
            ->withStatus($status)
            ->withType('application/json')
            ->withStringBody(json_encode($body, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR));
    }
}
