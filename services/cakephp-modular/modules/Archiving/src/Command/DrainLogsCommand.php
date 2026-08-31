<?php
declare(strict_types=1);

namespace Archiving\Command;

use Archiving\Gateway\DynamoGateway;
use Cake\Command\Command;
use Cake\Console\Arguments;
use Cake\Console\ConsoleIo;
use Cake\ORM\Locator\LocatorAwareTrait;

/**
 * アウトボックスに溜まったログを DynamoDB へ流すワーカー。
 *
 * 常駐させるか、cron で定期実行する。
 * 本番(Lambda)では EventBridge から定期起動する想定。
 */
class DrainLogsCommand extends Command
{
    use LocatorAwareTrait;

    private const MAX_ATTEMPTS = 5;

    public function execute(Arguments $args, ConsoleIo $io): int
    {
        $table = $this->fetchTable('Archiving.PendingLogs');
        $gateway = new DynamoGateway();

        $pending = $table->find()
            ->where(['attempts <' => self::MAX_ATTEMPTS])
            ->orderByAsc('id')
            ->limit(100)
            ->all();

        $done = 0;
        foreach ($pending as $row) {
            try {
                $gateway->put(
                    $row->log_type,
                    $row->owner_id,
                    (array)json_decode($row->payload, true),
                    new \DateTimeImmutable($row->occurred_at)
                );
                $table->delete($row);
                $done++;
            } catch (\Throwable $e) {
                // DynamoDB のスロットリングは時間を置けば回復する。
                // 試行回数だけ増やして次回に回す（無限リトライは避ける）。
                $row->set('attempts', $row->attempts + 1);
                $table->save($row);
                $io->err('アーカイブに失敗: ' . $e->getMessage());
            }
        }

        $io->out(sprintf('%d 件をアーカイブしました', $done));

        return static::CODE_SUCCESS;
    }
}
