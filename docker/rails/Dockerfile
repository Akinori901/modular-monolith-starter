# syntax=docker/dockerfile:1

FROM ruby:3.4-slim AS base
WORKDIR /app

# pg のビルドに必要なもの
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        build-essential libpq-dev libyaml-dev git curl \
    && rm -rf /var/lib/apt/lists/*

ENV BUNDLE_PATH=/usr/local/bundle \
    BUNDLE_JOBS=4 \
    RAILS_LOG_TO_STDOUT=1

FROM base AS deps
COPY Gemfile Gemfile.lock* ./
# rubygems は取りこぼすことがあるためリトライを設定する。
# 無いとネットワークが少し不安定なだけでビルドが落ちる。
RUN bundle config set --local retry 5 \
    && bundle install

# ── 開発用 ───────────────────────────────────────────────────
# ソースはマウントするので COPY しない（編集が即反映される）。
FROM deps AS dev
EXPOSE 3000

# ── 本番（Lambda コンテナイメージ）─────────────────────────────
FROM public.ecr.aws/lambda/ruby:3.4 AS lambda
COPY --from=deps /usr/local/bundle /usr/local/bundle
COPY . ${LAMBDA_TASK_ROOT}/
ENV BUNDLE_PATH=/usr/local/bundle \
    RAILS_ENV=production \
    RAILS_LOG_TO_STDOUT=1 \
    # Lambda では /tmp 以外書き込み不可。tmp をそこへ逃がす。
    TMPDIR=/tmp
CMD ["lambda_handler.handler"]
