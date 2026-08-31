<?php
declare(strict_types=1);

namespace Archiving\Model\Table;

use Cake\ORM\Table;

/**
 * アウトボックステーブル。
 *
 * **なぜキューではなくテーブルか:**
 * cakephp/queue は symfony/config ^6|^7 を要求するが、
 * CakePHP 5.4 は symfony/config v8 を引くため解決できない（実際に踏んだ）。
 *
 * 依存を無理に下げるより、DB へ一旦書いてワーカーが拾う
 * **アウトボックス方式**にした。実案件でも一般的な形で、
 * 「アプリの書き込みと同じトランザクションに乗せられる」利点もある。
 */
class PendingLogsTable extends Table
{
    public function initialize(array $config): void
    {
        parent::initialize($config);

        $this->setTable('pending_logs');
        $this->setPrimaryKey('id');
        $this->setEntityClass(\Archiving\Model\Entity\PendingLog::class);
    }
}
