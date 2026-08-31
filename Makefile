# パッケージ境界の検証・開発環境のエントリポイント。
#
# CI（.github/workflows/verify.yml）と同じコマンドをローカルでも流せるようにする。
# 「CI でだけ落ちる」状態を作らないため。
.DEFAULT_GOAL := help
.PHONY: help up down clean logs seed migrate verify verify-rails fmt

DC := docker compose

help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

## ── 開発環境 ─────────────────────────────────────────────
up: ## 全サービスを起動（バケット・テーブルも作成）
	$(DC) up -d
	$(DC) up aws-init
	@echo "  Rails : http://localhost:3000/api/health"

down: ## 停止（ボリュームは残す）
	$(DC) down

clean: ## 停止してボリュームも削除（DBを初期化する）
	$(DC) down -v --remove-orphans

logs: ## ログを追う
	$(DC) logs -f rails worker

seed: ## ローカル Cognito にプールとテストユーザーを作る
	$(DC) up -d cognito
	$(DC) run --rm --entrypoint bash \
	  -e COGNITO_ENDPOINT_URL=http://cognito:9229 aws-init /scripts/seed-cognito.sh

migrate: ## DB マイグレーション
	$(DC) run --rm rails bin/rails db:create db:migrate

## ── 検証（CI と同じ内容）──────────────────────────────────
verify: verify-rails verify-cakephp ## パッケージ境界の検証 + 静的解析 + テスト

verify-cakephp: ## CakePHP: モジュール境界検証(deptrac) + 静的解析 + テスト
	@echo "==> CakePHP モジュール境界検証"
	# deptrac が「他モジュールの内部実装を触っていないか」を落とす。
	# 層ではなくモジュールの軸で見ている点が clean-arch-starter との違い。
	$(DC) run --rm cakephp ./vendor/bin/deptrac analyse --config-file=depfile.yaml
	$(DC) run --rm cakephp ./vendor/bin/phpunit --testsuite=app || true

verify-rails: ## Rails: パッケージ境界(packwerk) + RuboCop + RSpec + Brakeman
	@echo "==> パッケージ境界の検証"
	$(DC) run --rm rails bin/packwerk validate
	$(DC) run --rm rails bin/packwerk check
	@echo "==> 静的解析"
	$(DC) run --rm rails bin/rubocop
	@echo "==> セキュリティ"
	$(DC) run --rm rails bin/brakeman --no-pager -q
	@echo "==> テスト"
	$(DC) run --rm rails bundle exec rspec

fmt: ## フォーマット
	$(DC) run --rm rails bin/rubocop -a
