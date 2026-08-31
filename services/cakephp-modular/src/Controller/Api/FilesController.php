<?php
declare(strict_types=1);

namespace App\Controller\Api;

use App\Controller\AppController;
use Archiving\Public\ArchivingApi;
use Storage\Exception\StorageException;
use Storage\Public\StorageApi;

/**
 * S3 へのアップロードと、DynamoDB への操作ログ記録。
 *
 * **認証 → 保存 → アーカイブ**という流れを1本で示す。
 */
class FilesController extends AppController
{
    public function create(): void
    {
        $user = $this->requireAuthentication();
        if ($user === null) {
            return;
        }

        $file = $this->request->getUploadedFile('file');
        if ($file === null) {
            $this->respond(['detail' => 'file は必須です'], 400);

            return;
        }

        try {
            $stored = (new StorageApi())->upload(
                (string)$user['user_id'],
                (string)$file->getClientFilename(),
                (string)$file->getStream(),
                (string)($file->getClientMediaType() ?: 'application/octet-stream')
            );
        } catch (StorageException $e) {
            $this->respond(['detail' => $e->getMessage()], 502);

            return;
        }

        // 操作ログは**非同期**。アップロード自体は既に成功しているので、
        // ログの書き込みで応答を待たせない。
        (new ArchivingApi())->recordLater(ArchivingApi::OPERATION, (string)$user['user_id'], [
            'event' => 'file_uploaded',
            'key' => $stored['key'],
            'size' => $stored['size'],
        ]);

        $this->respond($stored, 201);
    }

    public function presign(): void
    {
        if ($this->requireAuthentication() === null) {
            return;
        }

        $key = (string)$this->request->getQuery('key');
        if ($key === '') {
            $this->respond(['detail' => 'key は必須です'], 400);

            return;
        }

        // ファイル本体をアプリで中継しない。署名付き URL を返して
        // クライアントに直接 S3 を叩かせる（帯域と実行時間の節約）。
        $this->respond(['url' => (new StorageApi())->presignedUrl($key)], 200);
    }
}
