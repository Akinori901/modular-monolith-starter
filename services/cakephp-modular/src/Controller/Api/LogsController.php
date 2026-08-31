<?php
declare(strict_types=1);

namespace App\Controller\Api;

use App\Controller\AppController;
use Archiving\Exception\ArchiveException;
use Archiving\Public\ArchivingApi;

/** アーカイブされたログの参照。 */
class LogsController extends AppController
{
    public function index(): void
    {
        $user = $this->requireAuthentication();
        if ($user === null) {
            return;
        }

        $limit = max(1, min(200, (int)($this->request->getQuery('limit') ?? 50)));

        try {
            $entries = (new ArchivingApi())->recent(
                (string)($this->request->getQuery('log_type') ?? ArchivingApi::AUDIT),
                (string)$user['user_id'],
                $limit
            );
        } catch (ArchiveException $e) {
            $this->respond(['detail' => $e->getMessage()], 502);

            return;
        }

        $this->respond(['entries' => $entries], 200);
    }
}
