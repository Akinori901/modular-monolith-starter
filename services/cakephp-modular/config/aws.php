<?php
declare(strict_types=1);

/**
 * 外部サービスの設定を1か所に集約する。
 *
 * 各モジュールが env() を直接読むと、
 * 「何を設定すれば動くのか」がコード全体に散らばって追えなくなる。
 *
 * endpoint 系はローカル（cognito-local / SeaweedFS / DynamoDB Local）を
 * 指すときだけ設定する。本番では空にして AWS の既定エンドポイントを使う。
 */
return [
    'Cognito' => [
        'region' => env('AWS_REGION', 'ap-northeast-1'),
        'user_pool_id' => env('COGNITO_USER_POOL_ID', ''),
        'client_id' => env('COGNITO_CLIENT_ID', ''),
        'client_secret' => env('COGNITO_CLIENT_SECRET', ''),
        'endpoint' => env('COGNITO_ENDPOINT', ''),
        // エミュレータは自分の公開URL(localhost)を iss に刻む一方、
        // コンテナからは別ホスト名でしか到達できない。両者を分けて指定する。
        'issuer_override' => env('COGNITO_ISSUER_OVERRIDE', ''),
        'jwks_url_override' => env('COGNITO_JWKS_URL_OVERRIDE', ''),
    ],

    'S3' => [
        'region' => env('AWS_REGION', 'ap-northeast-1'),
        'bucket' => env('S3_BUCKET', 'app-uploads'),
        'endpoint' => env('S3_ENDPOINT', ''),
    ],

    'DynamoDb' => [
        'region' => env('AWS_REGION', 'ap-northeast-1'),
        'table' => env('DYNAMODB_TABLE', 'app-logs'),
        'endpoint' => env('DYNAMODB_ENDPOINT', ''),
        // TTL。保持期間を過ぎたログは DynamoDB が自動削除する。
        'retention_days' => env('LOG_RETENTION_DAYS', '365'),
    ],
];
