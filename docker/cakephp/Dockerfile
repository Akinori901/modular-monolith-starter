# syntax=docker/dockerfile:1

FROM php:8.4-cli AS base
WORKDIR /app

# CakePHP は ext-intl を必須とする（composer install が解決に失敗する）。
# pdo_mysql ではなく pdo_pgsql なのは、本リポジトリの DB が PostgreSQL のため。
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        git unzip libicu-dev libzip-dev libpq-dev \
    && docker-php-ext-configure intl \
    && docker-php-ext-install -j"$(nproc)" intl zip pdo_pgsql bcmath \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

ENV COMPOSER_ALLOW_SUPERUSER=1

# ── 依存インストール ──────────────────────────────────────────
FROM base AS deps
COPY composer.json composer.lock* ./
# rubygems 同様 packagist も取りこぼすことがあるためリトライを設定する
RUN composer install --no-interaction --no-scripts --no-autoloader --prefer-dist \
    || composer install --no-interaction --no-scripts --no-autoloader --prefer-dist

# ── 開発用 ───────────────────────────────────────────────────
# ソースはマウントするので COPY しない（編集が即反映される）。
FROM deps AS dev
EXPOSE 8765

# ── 本番（Lambda コンテナイメージ / Bref）─────────────────────
FROM bref/php-84-fpm:3 AS lambda
COPY --from=deps /app/vendor /var/task/vendor
COPY . /var/task/
# Lambda では /tmp 以外書き込み不可。tmp/logs をそこへ逃がす。
# 忘れるとキャッシュ書き込みで 500 になる（本番でだけ落ちる典型）。
ENV CAKE_TMP=/tmp
CMD ["webroot/index.php"]
