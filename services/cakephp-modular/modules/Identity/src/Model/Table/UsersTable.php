<?php
declare(strict_types=1);

namespace Identity\Model\Table;

use Cake\ORM\Table;
use Cake\Validation\Validator;

/**
 * Users テーブル。
 *
 * **CakePHP ウェイに逆らわない。** Repository で包んだりしない。
 * 代わりに「このテーブルを誰が触ってよいか」を deptrac が制御する。
 *
 * Table はモジュールの内部実装であり、`Public\` に出していないため
 * 他モジュール・Controller からは参照できない。
 */
class UsersTable extends Table
{
    public function initialize(array $config): void
    {
        parent::initialize($config);

        $this->setTable('users');
        // Cognito の sub を主キーにする（採番を Cognito に委ねる）
        $this->setPrimaryKey('id');
        $this->setEntityClass(\Identity\Model\Entity\User::class);
        $this->addBehavior('Timestamp');
    }

    public function validationDefault(Validator $validator): Validator
    {
        return $validator
            ->requirePresence('email', 'create')
            ->email('email', false, 'メールアドレスの形式が不正です')
            ->requirePresence('display_name', 'create')
            ->maxLength('display_name', 50, '表示名は50文字以内にしてください');
    }
}
