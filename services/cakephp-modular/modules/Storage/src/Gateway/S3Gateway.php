<?php
declare(strict_types=1);

namespace Storage\Gateway;

use Aws\Exception\AwsException;
use Aws\S3\S3Client;
use Cake\Core\Configure;
use Storage\Exception\StorageException;

/**
 * S3（本番）/ SeaweedFS（ローカル）とのやり取りを閉じ込める。
 *
 * endpoint を差し替えるだけで両方に対応する。
 * S3 互換 API を使う限り、コードは共通で済む。
 */
class S3Gateway
{
    private S3Client $client;
    private string $bucket;

    public function __construct(?S3Client $client = null)
    {
        $config = (array)Configure::read('S3');
        $this->bucket = (string)$config['bucket'];

        $args = ['version' => 'latest', 'region' => $config['region']];
        if (!empty($config['endpoint'])) {
            $args['endpoint'] = $config['endpoint'];
            // SeaweedFS 等の S3 互換実装は仮想ホスト形式に対応しないことがある
            $args['use_path_style_endpoint'] = true;
        }

        $this->client = $client ?? new S3Client($args);
    }

    public function put(string $key, string $body, string $contentType): void
    {
        try {
            $this->client->putObject([
                'Bucket' => $this->bucket,
                'Key' => $key,
                'Body' => $body,
                'ContentType' => $contentType,
            ]);
        } catch (AwsException $e) {
            throw new StorageException('アップロードに失敗しました: ' . $e->getAwsErrorMessage());
        }
    }

    public function get(string $key): ?string
    {
        try {
            return (string)$this->client->getObject([
                'Bucket' => $this->bucket,
                'Key' => $key,
            ])['Body'];
        } catch (AwsException $e) {
            if ($e->getAwsErrorCode() === 'NoSuchKey') {
                return null;
            }
            throw new StorageException('取得に失敗しました: ' . $e->getAwsErrorMessage());
        }
    }

    /**
     * 署名付き URL。**ファイル本体をアプリで中継しない**ための仕組み。
     * 中継するとメモリと実行時間を無駄に食う。
     */
    public function presignedUrl(string $key, int $expiresIn = 900): string
    {
        $command = $this->client->getCommand('GetObject', [
            'Bucket' => $this->bucket,
            'Key' => $key,
        ]);

        return (string)$this->client
            ->createPresignedRequest($command, "+{$expiresIn} seconds")
            ->getUri();
    }

    /**
     * 疎通確認。オブジェクト一覧ではなく HeadBucket を使う。
     * 必要な権限が最小で済み、バケットの中身の量に影響されない。
     */
    public function ping(): void
    {
        $this->client->headBucket(['Bucket' => $this->bucket]);
    }
}
