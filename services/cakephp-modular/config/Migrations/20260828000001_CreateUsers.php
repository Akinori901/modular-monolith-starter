<?php
declare(strict_types=1);

use Migrations\BaseMigration;

/**
 * users テーブル。
 *
 * Cognito の sub をそのまま主キーにするため、自動採番の id を使わない。
 */
class CreateUsers extends BaseMigration
{
    public function change(): void
    {
        $this->table('users', ['id' => false, 'primary_key' => ['id']])
            ->addColumn('id', 'string', ['limit' => 64, 'null' => false])
            ->addColumn('email', 'string', ['limit' => 254, 'null' => false])
            ->addColumn('display_name', 'string', ['limit' => 50, 'null' => false])
            ->addColumn('is_active', 'boolean', ['null' => false, 'default' => true])
            ->addColumn('created', 'datetime', ['null' => false, 'default' => 'CURRENT_TIMESTAMP'])
            ->addColumn('modified', 'datetime', ['null' => false, 'default' => 'CURRENT_TIMESTAMP'])
            ->addIndex(['email'], ['unique' => true])
            ->create();
    }
}
