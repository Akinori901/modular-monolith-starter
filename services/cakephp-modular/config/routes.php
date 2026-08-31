<?php
declare(strict_types=1);

use Cake\Routing\Route\DashedRoute;
use Cake\Routing\RouteBuilder;

return function (RouteBuilder $routes): void {
    $routes->setRouteClass(DashedRoute::class);

    $routes->scope('/api', function (RouteBuilder $builder): void {
        $builder->setExtensions(['json']);

        $builder->connect('/health', ['controller' => 'Health', 'action' => 'index', 'prefix' => 'Api'])
            ->setMethods(['GET']);
        $builder->connect('/health/live', ['controller' => 'Health', 'action' => 'live', 'prefix' => 'Api'])
            ->setMethods(['GET']);

        $builder->connect('/auth/sign-in', ['controller' => 'Sessions', 'action' => 'create', 'prefix' => 'Api'])
            ->setMethods(['POST']);
        $builder->connect('/auth/me', ['controller' => 'Sessions', 'action' => 'me', 'prefix' => 'Api'])
            ->setMethods(['GET']);

        $builder->connect('/files', ['controller' => 'Files', 'action' => 'create', 'prefix' => 'Api'])
            ->setMethods(['POST']);
        $builder->connect('/files/presign', ['controller' => 'Files', 'action' => 'presign', 'prefix' => 'Api'])
            ->setMethods(['GET']);

        $builder->connect('/logs', ['controller' => 'Logs', 'action' => 'index', 'prefix' => 'Api'])
            ->setMethods(['GET']);
    });
};
