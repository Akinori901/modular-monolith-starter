<?php
declare(strict_types=1);

namespace Identity\Model\Entity;

use Cake\ORM\Entity;

/**
 * User エンティティ。
 *
 * **CakePHP は Rails の ActiveRecord と違い、Table（クエリ）と
 * Entity（行）が最初から分離している。** そのぶんエンティティは
 * 素の PHP オブジェクトに近く、ビジネスルールを持たせやすい。
 *
 * ただし Table/Entity ともにモジュールの内部実装であり、
 * `Public\` 以外から参照すると deptrac が落とす。
 *
 * @property string $id
 * @property string $email
 * @property string $display_name
 * @property bool $is_active
 */
class User extends Entity
{
    protected array $_accessible = [
        'email' => true,
        'display_name' => true,
        'is_active' => true,
    ];

    /**
     * サインイン可能かを判定する（ビジネスルール）。
     *
     * この判定を Controller や UseCase の if で書かないこと。
     * エンティティに置かないと、同じ判定が各所へ散らばる。
     */
    public function canSignIn(): bool
    {
        return (bool)$this->is_active;
    }

    public function deactivate(): void
    {
        $this->set('is_active', false);
    }
}
