<?php
declare(strict_types=1);

use Migrations\BaseMigration;

/**
 * 非同期アーカイブ待ちのログ（アウトボックス）。
 *
 * cakephp/queue が CakePHP 5.4 と依存解決できないため、
 * DB へ一旦書いてワーカー(DrainLogsCommand)が拾う方式にしている。
 */
class CreatePendingLogs extends BaseMigration
{
    public function change(): void
    {
        $this->table('pending_logs')
            ->addColumn('log_type', 'string', ['limit' => 32, 'null' => false])
            ->addColumn('owner_id', 'string', ['limit' => 128, 'null' => false])
            ->addColumn('payload', 'text', ['null' => false])
            ->addColumn('occurred_at', 'string', ['limit' => 64, 'null' => false])
            // 失敗が続くものを無限に再試行しないための試行回数
            ->addColumn('attempts', 'integer', ['null' => false, 'default' => 0])
            ->addIndex(['attempts'])
            ->create();
    }
}
