<?php
declare(strict_types=1);

namespace Archiving\Test\TestCase\Listener;

use Archiving\Listener\IdentityEventListener;
use Archiving\Public\ArchivingApi;
use Cake\Event\Event;
use Cake\Event\EventManager;
use Cake\TestSuite\TestCase;
use Identity\UseCase\SignInUseCase;

/**
 * **モジュール間がイベントで繋がっていることのテスト。**
 *
 * Identity は Archiving を知らないまま、Archiving 側が購読する。
 * deptrac が見るのは「境界を越えていないか」であって、
 * 「イベントが実際に繋がっているか」は見られない。
 *
 * 発行側と購読側は**イベント名の文字列でしか繋がっていない**ため、
 * 片方だけ変えると黙って届かなくなる。これが疎結合の代金であり、
 * その一致を保証できるのはこのテストだけ。
 *
 * ※ 発行側の定数（SignInUseCase::EVENT_*）を参照しているのはテストだからで、
 *    本番コードの Listener から参照してはならない（deptrac が落とす）。
 *    テストが「両者を見比べる」役を担うことで、依存を作らずに一致を守る。
 */
class IdentityEventListenerTest extends TestCase
{
    private EventManager $manager;

    protected function setUp(): void
    {
        parent::setUp();
        $this->manager = new EventManager();
    }

    /**
     * 購読しているイベント名が、発行側の定数と一致すること。
     *
     * **これが本命。** 名前がずれた瞬間にここが落ちる。
     */
    public function testSubscribedEventNamesMatchPublisher(): void
    {
        $listener = new IdentityEventListener(new SpyArchivingApi());

        $subscribed = array_keys($listener->implementedEvents());

        $this->assertContains(
            SignInUseCase::EVENT_SIGN_IN,
            $subscribed,
            'サインイン成功イベントの購読名が発行側とずれている'
        );
        $this->assertContains(
            SignInUseCase::EVENT_SIGN_IN_FAILURE,
            $subscribed,
            'サインイン失敗イベントの購読名が発行側とずれている'
        );
    }

    /** サインイン成功は**同期**で記録する（監査ログは失ってはならない） */
    public function testSignInIsRecordedSynchronously(): void
    {
        $spy = new SpyArchivingApi();
        $this->manager->on(new IdentityEventListener($spy));

        $this->manager->dispatch(new Event(SignInUseCase::EVENT_SIGN_IN, $this, [
            'user_id' => 'sub-1',
            'email' => 'taro@example.com',
            'ip' => '127.0.0.1',
            'user_agent' => 'test',
        ]));

        $this->assertCount(1, $spy->recorded, '同期で記録されていない');
        $this->assertSame([], $spy->recordedLater, '成功を非同期で記録してはならない');
        $this->assertSame(ArchivingApi::AUDIT, $spy->recorded[0]['log_type']);
        $this->assertSame('sub-1', $spy->recorded[0]['owner_id']);
        $this->assertSame('sign_in', $spy->recorded[0]['payload']['event']);
    }

    /** サインイン失敗は**非同期**で記録する（攻撃時に大量発生するため） */
    public function testSignInFailureIsRecordedAsynchronously(): void
    {
        $spy = new SpyArchivingApi();
        $this->manager->on(new IdentityEventListener($spy));

        $this->manager->dispatch(new Event(SignInUseCase::EVENT_SIGN_IN_FAILURE, $this, [
            'email' => 'nobody@example.com',
            'ip' => '127.0.0.1',
            'reason' => 'invalid_credentials',
        ]));

        $this->assertCount(1, $spy->recordedLater, '非同期で記録されていない');
        $this->assertSame([], $spy->recorded, '失敗を同期で記録してはならない');
        // 認証前なので user_id が無い。IP を所有者キーにする。
        $this->assertSame('127.0.0.1', $spy->recordedLater[0]['owner_id']);
        $this->assertSame('sign_in_failure', $spy->recordedLater[0]['payload']['event']);
    }
}

/**
 * DynamoDB へ行かせずに呼び出しだけ捕まえる。
 *
 * ここで見たいのは「同期 / 非同期のどちらで呼ばれたか」であって
 * 書き込みの中身ではないため、Gateway は起動しない。
 */
class SpyArchivingApi extends ArchivingApi
{
    /** @var list<array<string, mixed>> */
    public array $recorded = [];

    /** @var list<array<string, mixed>> */
    public array $recordedLater = [];

    public function __construct()
    {
    }

    /** @param array<string, mixed> $payload */
    public function record(string $logType, string $ownerId, array $payload): string
    {
        $this->recorded[] = ['log_type' => $logType, 'owner_id' => $ownerId, 'payload' => $payload];

        return 'spy-id';
    }

    /** @param array<string, mixed> $payload */
    public function recordLater(string $logType, string $ownerId, array $payload): void
    {
        $this->recordedLater[] = ['log_type' => $logType, 'owner_id' => $ownerId, 'payload' => $payload];
    }
}
