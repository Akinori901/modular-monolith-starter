<?php
declare(strict_types=1);

namespace Identity\UseCase;

use Cake\Event\EventManager;
use Cake\ORM\Locator\LocatorAwareTrait;
use Identity\Exception\AuthenticationFailedException;
use Identity\Gateway\CognitoGateway;
use Identity\Model\Entity\User;

/**
 * サインインのユースケース。
 *
 * **UseCase の役割は「手順の組み立て」だけ。**
 * ビジネスルール（サインイン可否の判定など）はエンティティが持つ。
 * ここに if でルールを書き始めたら、エンティティが貧血症になっている合図。
 *
 * Controller に全部書くと、同じ手順を Command や Job から
 * 呼びたくなったときに再利用できない。UseCase はそのための層。
 */
class SignInUseCase
{
    use LocatorAwareTrait;

    public const EVENT_SIGN_IN = 'Identity.signIn';
    public const EVENT_SIGN_IN_FAILURE = 'Identity.signInFailure';

    public function __construct(
        private readonly CognitoGateway $cognito = new CognitoGateway(),
    ) {
    }

    /**
     * @return array{tokens:array<string,mixed>,user:\Identity\Model\Entity\User}
     * @throws \Identity\Exception\AuthenticationFailedException
     */
    public function execute(string $email, string $password, ?string $ip = null, ?string $userAgent = null): array
    {
        try {
            // 1. 認証基盤（Cognito）で認証する
            $tokens = $this->cognito->signIn($email, $password);

            // 2. 検証済みトークンから本人を特定する
            $identity = $this->cognito->verifyAccessToken($tokens['access_token']);

            // 3. ローカル側のユーザーを解決する（初回サインインなら作る）
            //    Cognito が正で、ローカルはプロフィールの保持のみを担う。
            $user = $this->resolveUser($identity['subject'], $email);

            // 4. 無効化されたアカウントは、Cognito 側が通しても拒否する。
            //    判定規則はエンティティが持つ。ここでは呼ぶだけ。
            if (!$user->canSignIn()) {
                $this->dispatchFailure($email, $ip, 'deactivated');
                throw new AuthenticationFailedException('このアカウントは無効化されています');
            }
        } catch (AuthenticationFailedException $e) {
            if (!str_contains($e->getMessage(), '無効化')) {
                $this->dispatchFailure($email, $ip, 'invalid_credentials');
            }
            throw $e;
        }

        // 5. 監査ログは**同期**で残す。
        //    「誰がいつサインインしたか」は後から復元できないため、
        //    書けなかったらサインイン自体を失敗させる。
        EventManager::instance()->dispatch(new \Cake\Event\Event(self::EVENT_SIGN_IN, $this, [
            'user_id' => $user->id,
            'email' => $email,
            'ip' => $ip,
            'user_agent' => $userAgent,
        ]));

        return ['tokens' => $tokens, 'user' => $user];
    }

    private function resolveUser(string $subject, string $email): User
    {
        $users = $this->fetchTable('Identity.Users');

        /** @var \Identity\Model\Entity\User|null $existing */
        $existing = $users->find()->where(['id' => $subject])->first();
        if ($existing !== null) {
            return $existing;
        }

        $user = $users->newEntity([
            'email' => $email,
            'display_name' => explode('@', $email)[0],
            'is_active' => true,
        ]);
        $user->set('id', $subject);
        $users->saveOrFail($user);

        return $user;
    }

    /**
     * 認証失敗も監査対象。**失敗の記録で本体を落とさない**ため、
     * ここは書けなくても握りつぶす（ログには残す）。
     */
    private function dispatchFailure(string $email, ?string $ip, string $reason): void
    {
        try {
            EventManager::instance()->dispatch(new \Cake\Event\Event(self::EVENT_SIGN_IN_FAILURE, $this, [
                'email' => $email,
                'ip' => $ip,
                'reason' => $reason,
            ]));
        } catch (\Throwable $e) {
            \Cake\Log\Log::error('監査ログの記録に失敗: ' . $e->getMessage());
        }
    }
}
