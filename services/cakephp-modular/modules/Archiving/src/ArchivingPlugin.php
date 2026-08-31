<?php
declare(strict_types=1);

namespace Archiving;

use Cake\Core\BasePlugin;

/**
 * Archiving モジュールをプラグインとして登録するためのクラス。
 *
 * **CakePHP 5.3 以降、プラグインクラスの無いプラグイン読み込みは deprecated。**
 * 無いと Deprecated 警告がレスポンスに混ざり、JSON が壊れる（実際に踏んだ）。
 *
 * ルーティング・bootstrap は持たない。
 * このモジュールが公開するのは Archiving\Public\ 配下だけで、
 * HTTP の入口はアプリ本体(App\Controller)が持つ。
 */
class ArchivingPlugin extends BasePlugin
{
    protected bool $routesEnabled = false;
    protected bool $bootstrapEnabled = false;
    protected bool $middlewareEnabled = false;
}
