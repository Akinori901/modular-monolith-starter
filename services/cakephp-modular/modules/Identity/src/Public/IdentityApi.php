<?php
declare(strict_types=1);

namespace Identity\Public;

use Cake\ORM\Locator\LocatorAwareTrait;
use Identity\Exception\AuthenticationFailedException;
use Identity\Gateway\CognitoGateway;
use Identity\Model\Entity\User;
use Identity\UseCase\SignInUseCase;

/**
 * Identity モジュールの**公開 API**。
 *
 * 他モジュール・Controller から触ってよいのはこのクラスだけ。
 * Model / UseCase / Gateway / Service はすべて内部実装であり、
 * 外から参照すると deptrac が落とす。
 *
 * 公開面を1枚に絞ることで、内部をいくら作り替えても
 * 呼び出し側が壊れない状態を保つ。
 */
class IdentityApi
{
    use LocatorAwareTrait;

    /**
     * サインインする。
     *
     * @return array{tokens:array<string,mixed>,user:array<string,mixed>}
     * @throws \Identity\Exception\AuthenticationFailedException
     */
    public function signIn(string $email, string $password, ?string $ip = null, ?string $userAgent = null): array
    {
        $result = (new SignInUseCase())->execute($email, $password, $ip, $userAgent);

        return [
            'tokens' => $result['tokens'],
            'user' => $this->toView($result['user']),
        ];
    }

    /**
     * アクセストークンから現在のユーザーを返す。
     *
     * @return array<string, mixed>
     * @throws \Identity\Exception\AuthenticationFailedException
     */
    public function currentUser(string $accessToken): array
    {
        $identity = (new CognitoGateway())->verifyAccessToken($accessToken);

        /** @var \Identity\Model\Entity\User|null $user */
        $user = $this->fetchTable('Identity.Users')
            ->find()->where(['id' => $identity['subject']])->first();

        if ($user === null) {
            throw new AuthenticationFailedException('ユーザーが見つかりません');
        }

        return $this->toView($user);
    }

    /** 疎通確認（ヘルスチェック用） */
    public function ping(): void
    {
        (new CognitoGateway())->ping();
    }

    /**
     * 公開する形。**Entity をそのまま返さない。**
     * 返すと呼び出し側がテーブル構造に依存してしまう。
     *
     * @return array<string, mixed>
     */
    private function toView(User $user): array
    {
        return [
            'user_id' => $user->id,
            'email' => $user->email,
            'display_name' => $user->display_name,
            'is_active' => $user->canSignIn(),
        ];
    }
}
