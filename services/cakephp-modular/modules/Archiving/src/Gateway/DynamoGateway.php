<?php
declare(strict_types=1);

namespace Archiving\Gateway;

use Archiving\Exception\ArchiveException;
use Aws\DynamoDb\DynamoDbClient;
use Aws\DynamoDb\Marshaler;
use Aws\Exception\AwsException;
use Cake\Core\Configure;
use Cake\Utility\Text;

/**
 * DynamoDB とのやり取りを閉じ込める。
 *
 * テーブル設計（Rails 版と同一。同じ app-logs テーブルを共有する）:
 *   PK = "<log_type>#<owner_id>"   例: "audit#user-123"
 *   SK = "<ISO8601 timestamp>#<uuid>"
 *
 * **時系列で引けることを優先した設計。**
 * 「あるユーザーの直近のログ」が SK の範囲検索だけで取れる。
 * GSI を足さずに済むぶん、書き込みコストも低い。
 *
 * TTL 属性(expires_at)を付けており、保持期間を過ぎたものは
 * DynamoDB 側が自動削除する（削除のためのバッチを書かない）。
 */
class DynamoGateway
{
    private DynamoDbClient $client;
    private Marshaler $marshaler;
    private string $table;
    private int $retentionDays;

    public function __construct(?DynamoDbClient $client = null)
    {
        $config = (array)Configure::read('DynamoDb');
        $this->table = (string)$config['table'];
        $this->retentionDays = (int)$config['retention_days'];

        $args = ['version' => 'latest', 'region' => $config['region']];
        if (!empty($config['endpoint'])) {
            $args['endpoint'] = $config['endpoint'];
        }

        $this->client = $client ?? new DynamoDbClient($args);
        $this->marshaler = new Marshaler();
    }

    /**
     * @param array<string, mixed> $payload
     */
    public function put(string $logType, string $ownerId, array $payload, ?\DateTimeImmutable $occurredAt = null): string
    {
        $at = $occurredAt ?? new \DateTimeImmutable('now', new \DateTimeZone('UTC'));
        $sk = $at->format('Y-m-d\TH:i:s.uP') . '#' . Text::uuid();

        $item = [
            'pk' => $logType . '#' . $ownerId,
            'sk' => $sk,
            'log_type' => $logType,
            'owner_id' => $ownerId,
            'occurred_at' => $at->format('Y-m-d\TH:i:s.uP'),
            // TTL。保持期間を過ぎたら DynamoDB が勝手に消す。
            'expires_at' => $at->modify("+{$this->retentionDays} days")->getTimestamp(),
            // 値の形が呼び出し側でまちまちになるため、文字列へ寄せて安定させる
            'payload' => array_map(
                static fn ($v): string => (string)$v,
                array_filter($payload, static fn ($v): bool => $v !== null)
            ),
        ];

        try {
            $this->client->putItem([
                'TableName' => $this->table,
                'Item' => $this->marshaler->marshalItem($item),
            ]);
        } catch (AwsException $e) {
            throw new ArchiveException('アーカイブに失敗しました: ' . $e->getAwsErrorMessage());
        }

        return $sk;
    }

    /**
     * 直近のログを新しい順に返す。
     *
     * @return list<array<string, mixed>>
     */
    public function query(string $logType, string $ownerId, int $limit = 50): array
    {
        try {
            $result = $this->client->query([
                'TableName' => $this->table,
                'KeyConditionExpression' => 'pk = :pk',
                'ExpressionAttributeValues' => $this->marshaler->marshalItem([
                    ':pk' => $logType . '#' . $ownerId,
                ]),
                // 新しい順（SK の降順）
                'ScanIndexForward' => false,
                'Limit' => $limit,
            ]);
        } catch (AwsException $e) {
            throw new ArchiveException('検索に失敗しました: ' . $e->getAwsErrorMessage());
        }

        return array_map(
            fn (array $item): array => $this->marshaler->unmarshalItem($item),
            $result['Items'] ?? []
        );
    }

    /** 疎通確認（ヘルスチェック用） */
    public function ping(): void
    {
        $this->client->describeTable(['TableName' => $this->table]);
    }
}
