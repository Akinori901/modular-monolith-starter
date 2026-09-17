# パッケージ境界の検証・開発環境のエントリポイント。
#
# CI（.github/workflows/verify.yml）と同じコマンドをローカルでも流せるようにする。
# 「CI でだけ落ちる」状態を作らないため。
.DEFAULT_GOAL := help
.PHONY: help up down clean logs seed migrate verify verify-rails verify-cakephp verify-phoenix fmt

DC := docker compose

help: ## このヘルプを表示
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}'

## ── 開発環境 ─────────────────────────────────────────────
up: ## 全サービスを起動（バケット・テーブルも作成）
	$(DC) up -d
	$(DC) up aws-init
	@echo "  Rails   : http://localhost:3000/api/health"
	@echo "  CakePHP : http://localhost:8765/api/health"
	@echo "  Phoenix : http://localhost:4000/api/health"

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

migrate: ## DB マイグレーション（各スタックとも DB 名は分けてある）
	$(DC) run --rm rails bin/rails db:create db:migrate
	$(DC) run --rm phoenix mix ecto.setup

## ── 検証（CI と同じ内容）──────────────────────────────────
verify: verify-rails verify-cakephp verify-phoenix ## パッケージ境界の検証 + 静的解析 + テスト

verify-cakephp: ## CakePHP: モジュール境界検証(deptrac) + PHPStan + PHPUnit
	@echo "==> CakePHP モジュール境界検証"
	# deptrac が「他モジュールの内部実装を触っていないか」を落とす。
	# 層ではなくモジュールの軸で見ている点が clean-arch-starter との違い。
	$(DC) run --rm cakephp ./vendor/bin/deptrac analyse --config-file=depfile.yaml
	@echo "==> 静的解析"
	# --memory-limit は必須。既定の 128M ではワーカーがクラッシュし、
	# 型エラーではなく「PHPStan process crashed」で解析が完走しない。
	$(DC) run --rm cakephp ./vendor/bin/phpstan analyse --no-progress --memory-limit=512M
	@echo "==> テスト"
	# **|| true を付けないこと。** 付けるとテストが落ちても verify が緑になり、
	# 「イベント名の突き合わせテストを必ず書く」という規約が強制力を失う。
	# deptrac は境界を越えていないかを見るが、イベントが実際に繋がっているかは見ない。
	# 発行側と購読側は文字列でしか繋がっていないため、そこはテストだけが守れる。
	$(DC) run --rm cakephp ./vendor/bin/phpunit --testsuite=app
	$(DC) run --rm cakephp ./vendor/bin/phpunit --testsuite=modules

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

verify-phoenix: ## Phoenix: Context境界(boundary) + Credo + ExUnit
	@echo "==> Context 境界の検証"
	# boundary は**コンパイラ**なので、境界違反はコンパイル警告として出る。
	# --warnings-as-errors を付けて初めて「落ちる」形になる。
	# packwerk と違い別コマンドが要らず、検証を忘れようがない。
	$(DC) run --rm -e MIX_ENV=test -e DB_NAME=app_phoenix_test phoenix \
	  mix compile --force --warnings-as-errors
	@echo "==> 静的解析"
	$(DC) run --rm -e MIX_ENV=test -e DB_NAME=app_phoenix_test phoenix mix credo
	@echo "==> テスト"
	$(DC) run --rm -e MIX_ENV=test -e DB_NAME=app_phoenix_test phoenix mix test

fmt: ## フォーマット
	$(DC) run --rm rails bin/rubocop -a
	$(DC) run --rm phoenix mix format
