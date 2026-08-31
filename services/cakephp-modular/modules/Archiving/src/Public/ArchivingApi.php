<?php
declare(strict_types=1);

namespace Archiving\Public;

use Archiving\Gateway\DynamoGateway;
use Cake\Queue\QueueManager;

/**
 * Archiving モジュールの**公開 API**。
 *
 * DynamoGateway は内部実装であり、外から参照すると deptrac が落とす。
 */
class ArchivingApi
{
    /** ログの種別。文字列を直接渡させない（打ち間違いを定数で防ぐ）。 */
    public const AUDIT = 'audit';
    public const ACCESS = 'access';
    public const OPERATION = 'operation';

    public function __construct(
        private readonly DynamoGateway $gateway = new DynamoGateway(),
    ) {
    }

    /**
     * **同期**で書き込む。
     *
     * 監査ログのように「書けなかったら処理自体を失敗させたい」ものに使う。
     * 呼び出し側は例外を受け取れる。
     *
     * @param array<string, mixed> $payload
     */
    public function record(string $logType, string $ownerId, array $payload): string
    {
        return $this->gateway->put($logType, $ownerId, $payload);
    }

    /**
     * **非同期**でキューに積む。
     *
     * アクセスログのように件数が多く、失っても業務が破綻しないものに使う。
     * リクエストの応答をブロックしない。
     *
     * @param array<string, mixed> $payload
     */
    public function recordLater(string $logType, string $ownerId, array $payload): void
    {
        QueueManager::push(
            [\Archiving\Job\ArchiveLogJob::class, 'execute'],
            [
                'log_type' => $logType,
                'owner_id' => $ownerId,
                'payload' => $payload,
                'occurred_at' => (new \DateTimeImmutable('now', new \DateTimeZone('UTC')))
                    ->format('Y-m-d\TH:i:s.uP'),
            ]
        );
    }

    /**
     * 直近のログを新しい順に返す。
     *
     * @return list<array<string, mixed>>
     */
    public function recent(string $logType, string $ownerId, int $limit = 50): array
    {
        return $this->gateway->query($logType, $ownerId, $limit);
    }

    public function ping(): void
    {
        $this->gateway->ping();
    }
}
