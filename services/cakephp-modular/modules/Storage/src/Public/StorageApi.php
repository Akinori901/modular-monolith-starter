<?php
declare(strict_types=1);

namespace Storage\Public;

use Storage\Gateway\S3Gateway;

/**
 * Storage モジュールの**公開 API**。
 *
 * S3Gateway は内部実装なので、外から参照すると deptrac が落とす。
 */
class StorageApi
{
    public function __construct(
        private readonly S3Gateway $gateway = new S3Gateway(),
    ) {
    }

    /**
     * ファイルを保存する。
     *
     * **キーは呼び出し側に決めさせず、ここで組み立てる。**
     * 呼び出し側が自由に決めると命名がバラバラになり、後で移行できない。
     *
     * @return array{key:string,size:int,content_type:string}
     */
    public function upload(string $ownerId, string $filename, string $body, string $contentType): array
    {
        $key = $this->buildKey($ownerId, $filename);
        $this->gateway->put($key, $body, $contentType);

        return ['key' => $key, 'size' => strlen($body), 'content_type' => $contentType];
    }

    public function download(string $key): ?string
    {
        return $this->gateway->get($key);
    }

    public function presignedUrl(string $key, int $expiresIn = 900): string
    {
        return $this->gateway->presignedUrl($key, $expiresIn);
    }

    public function ping(): void
    {
        $this->gateway->ping();
    }

    /**
     * uploads/<owner>/<YYYY/MM/DD>/<uuid>_<filename>
     *
     * 日付を挟むのは S3 のプレフィックス分散とライフサイクルルールのため。
     * UUID を付けるのは同名ファイルの衝突を避けるため。
     */
    private function buildKey(string $ownerId, string $filename): string
    {
        $safe = preg_replace('/[^\w.\-]/', '_', basename($filename)) ?? 'file';

        return sprintf(
            'uploads/%s/%s/%s_%s',
            $ownerId,
            date('Y/m/d'),
            \Cake\Utility\Text::uuid(),
            $safe
        );
    }
}
