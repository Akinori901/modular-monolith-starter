<?php
declare(strict_types=1);

namespace App\Controller\Api;

use App\Controller\AppController;
use Identity\Exception\AuthenticationFailedException;
use Identity\Public\IdentityApi;

/**
 * Controller がやってよいのは 3 つだけ:
 *   1. 入力の検証
 *   2. モジュールの公開 API 呼び出し
 *   3. 例外 → HTTP ステータスの変換
 *
 * **触ってよいのは Identity\Public\IdentityApi だけ。**
 * UsersTable や SignInUseCase を直接呼ぶと deptrac が落とす。
 */
class SessionsController extends AppController
{
    public function create(): void
    {
        $email = (string)$this->request->getData('email');
        $password = (string)$this->request->getData('password');

        if ($email === '' || strlen($password) < 8) {
            $this->respond(['detail' => 'メールアドレスとパスワード(8文字以上)は必須です'], 400);

            return;
        }

        try {
            $result = (new IdentityApi())->signIn(
                $email,
                $password,
                $this->request->clientIp(),
                $this->request->getHeaderLine('User-Agent')
            );
        } catch (AuthenticationFailedException $e) {
            // 業務の語彙（認証失敗）を HTTP の語彙（401）へ翻訳するのはここ
            $this->respond(['detail' => $e->getMessage()], 401);

            return;
        }

        $this->respond([
            'access_token' => $result['tokens']['access_token'],
            'id_token' => $result['tokens']['id_token'],
            'refresh_token' => $result['tokens']['refresh_token'],
            'expires_in' => $result['tokens']['expires_in'],
            'user' => $result['user'],
        ], 200);
    }

    public function me(): void
    {
        $user = $this->requireAuthentication();
        if ($user === null) {
            return;
        }

        $this->respond($user, 200);
    }
}
