# syntax=docker/dockerfile:1

FROM elixir:1.18-slim AS base
WORKDIR /app

# **ca-certificates が入っていない。**
# 入れないと hex.pm への TLS が失敗し、`mix deps.get` が
# 「証明書が検証できない」で落ちる（実際に踏んだ）。
#
# build-essential / git は依存のネイティブビルドに要る。
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        ca-certificates build-essential git curl \
    && rm -rf /var/lib/apt/lists/*

ENV MIX_HOME=/opt/mix \
    HEX_HOME=/opt/hex \
    ERL_AFLAGS="-kernel shell_history enabled" \
    # hex は取りこぼすことがある。並列を落として待ち時間を伸ばす。
    # 無いとネットワークが少し不安定なだけでビルドが落ちる（実際に踏んだ）。
    HEX_HTTP_CONCURRENCY=1 \
    HEX_HTTP_TIMEOUT=120

RUN mix local.hex --force && mix local.rebar --force

FROM base AS deps
COPY mix.exs mix.lock* ./
# deps.get と deps.compile を分けてレイヤに乗せる。
# ソースを変えただけで依存の再ビルドが走るのを避ける。
RUN mix deps.get && MIX_ENV=dev mix deps.compile

# ── 開発用 ───────────────────────────────────────────────────
# ソースはマウントするので COPY しない（編集が即反映される）。
FROM deps AS dev
ENV MIX_ENV=dev
EXPOSE 4000

# ── リリースビルド ────────────────────────────────────────────
# OTP リリースを作る。実行イメージに Elixir/Mix を持ち込まないため、
# ビルド用と実行用を分ける。
FROM base AS builder
ENV MIX_ENV=prod
COPY mix.exs mix.lock* ./
RUN mix deps.get --only prod && mix deps.compile
COPY config config
COPY lib lib
COPY priv priv
RUN mix compile --warnings-as-errors
COPY rel rel
RUN mix release

# ── 実行用 ───────────────────────────────────────────────────
# Erlang のランタイムだけを積む。Elixir も Mix も要らない。
#
# **ベースは builder と同じ Debian のバージョンに揃えること。**
# リリースには builder 側の ERTS（beam.smp / epmd）がそのまま入るため、
# 実行側の glibc が古いと起動時に
#   beam.smp: /lib/.../libc.so.6: version `GLIBC_2.38' not found
# で落ちる。elixir:1.18-slim は Debian 13(trixie/glibc 2.41) なので、
# bookworm(glibc 2.36) を実行側に使うと動かない（実際に踏んだ）。
FROM debian:trixie-slim AS runtime
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        ca-certificates libstdc++6 openssl libncurses6 locales \
    && rm -rf /var/lib/apt/lists/* \
    && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PHX_SERVER=true \
    # 書き込み可能な場所を明示する（Lambda / 読み取り専用 FS 対策）。
    TMPDIR=/tmp

WORKDIR /app
COPY --from=builder /app/_build/prod/rel/app ./
EXPOSE 4000
CMD ["bin/app", "start"]
