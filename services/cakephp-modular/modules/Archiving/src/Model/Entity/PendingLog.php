<?php
declare(strict_types=1);

namespace Archiving\Model\Entity;

use Cake\ORM\Entity;

/**
 * 非同期アーカイブ待ちのログ（アウトボックス）。
 *
 * @property int $id
 * @property string $log_type
 * @property string $owner_id
 * @property string $payload
 */
class PendingLog extends Entity
{
    protected array $_accessible = [
        'log_type' => true,
        'owner_id' => true,
        'payload' => true,
        'occurred_at' => true,
        'attempts' => true,
    ];
}
