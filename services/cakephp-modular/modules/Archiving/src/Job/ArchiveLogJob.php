<?php
declare(strict_types=1);

namespace Archiving\Job;

use Archiving\Gateway\DynamoGateway;
use Cake\Log\Log;
use Cake\Queue\Job\JobInterface;
use Cake\Queue\Job\Message;
use Interop\Queue\Processor;

/**
 * ログを非同期で DynamoDB へ書き込む Job。
 *
 * **非同期にしてよいのは「失っても業務が破綻しないログ」だけ。**
 * 監査ログ（誰がサインインしたか）は同期で書く。ArchivingApi::record() を参照。
 */
class ArchiveLogJob implements JobInterface
{
    public function execute(Message $message): ?string
    {
        $args = $message->getArgument();

        try {
            (new DynamoGateway())->put(
                (string)$args['log_type'],
                (string)$args['owner_id'],
                (array)$args['payload'],
                new \DateTimeImmutable((string)$args['occurred_at'])
            );
        } catch (\Throwable $e) {
            // DynamoDB のスロットリングは時間を置けば回復するため、再試行させる。
            Log::error('ログのアーカイブに失敗: ' . $e->getMessage());

            return Processor::REQUEUE;
        }

        return Processor::ACK;
    }
}
