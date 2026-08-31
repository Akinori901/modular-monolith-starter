<?php
declare(strict_types=1);

namespace Archiving\Listener;

use Archiving\Public\ArchivingApi;
use Cake\Event\EventInterface;
use Cake\Event\EventListenerInterface;

/**
 * Identity モジュールのイベントを購読してアーカイブする。
 *
 * **依存の向きがここで反転している点が重要。**
 * Identity が Archiving を呼ぶのではなく、Archiving が
 * Identity のイベントを聞きに行く。こうすると:
 *
 *   - Identity は Archiving を知らない（deptrac の依存表が空のまま）
 *   - アーカイブを止めても認証は動く
 *   - 購読者を増やしても Identity は変わらない
 *
 * 両者の接点はイベント名の文字列だけになる。
 */
class IdentityEventListener implements EventListenerInterface
{
    public function __construct(
        private readonly ArchivingApi $api = new ArchivingApi(),
    ) {
    }

    /**
     * @return array<string, string>
     */
    public function implementedEvents(): array
    {
        return [
            'Identity.signIn' => 'onSignIn',
            'Identity.signInFailure' => 'onSignInFailure',
        ];
    }

    /** サインイン成功は**同期**（監査ログ。失ってはならない） */
    public function onSignIn(EventInterface $event): void
    {
        $data = $event->getData();

        $this->api->record(ArchivingApi::AUDIT, (string)$data['user_id'], [
            'event' => 'sign_in',
            'email' => $data['email'] ?? null,
            'ip' => $data['ip'] ?? null,
            'user_agent' => $data['user_agent'] ?? null,
        ]);
    }

    /** サインイン失敗は**非同期**（攻撃時に大量発生するため） */
    public function onSignInFailure(EventInterface $event): void
    {
        $data = $event->getData();

        $this->api->recordLater(
            ArchivingApi::AUDIT,
            // 認証前なので user_id が無い。IP を所有者キーにする。
            (string)($data['ip'] ?? 'unknown'),
            [
                'event' => 'sign_in_failure',
                'email' => $data['email'] ?? null,
                'reason' => $data['reason'] ?? null,
            ]
        );
    }
}
