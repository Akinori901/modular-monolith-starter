<?php
declare(strict_types=1);

namespace App\Controller\Api;

use App\Controller\AppController;
use Archiving\Public\ArchivingApi;
use Cake\Datasource\ConnectionManager;
use Identity\Public\IdentityApi;
use Storage\Public\StorageApi;

/**
 * ヘルスチェック。
 *
 * 各依存の疎通確認。1つ落ちても残りは確認する
 * （全体像が見えないと切り分けができない）。
 */
class HealthController extends AppController
{
    public function index(): void
    {
        $components = [
            $this->probe('database', fn () => ConnectionManager::get('default')->execute('SELECT 1')),
            $this->probe('object_storage', fn () => (new StorageApi())->ping()),
            $this->probe('cognito', fn () => (new IdentityApi())->ping()),
            $this->probe('log_archive', fn () => (new ArchivingApi())->ping()),
        ];

        $healthy = !in_array('down', array_column($components, 'state'), true);

        // 依存が落ちていれば 503。ALB はステータスコードで判定するため、
        // 本文が返せていても 200 にしないこと。
        $this->respond(['healthy' => $healthy, 'components' => $components], $healthy ? 200 : 503);
    }

    /** プロセスの生存のみを見る（依存を確認しない） */
    public function live(): void
    {
        $this->respond(['status' => 'ok'], 200);
    }

    /**
     * @return array{name:string,state:string,detail:string}
     */
    private function probe(string $name, callable $check): array
    {
        try {
            $check();

            return ['name' => $name, 'state' => 'up', 'detail' => ''];
        } catch (\Throwable $e) {
            return ['name' => $name, 'state' => 'down', 'detail' => mb_substr($e->getMessage(), 0, 200)];
        }
    }
}
