import Config

# 実際の接続先・秘密情報は config/runtime.exs で環境変数から入れる。
# ここに書くとビルド時の値がイメージへ焼き込まれてしまう。
config :app, AppWeb.Endpoint, cache_static_manifest: nil

config :logger, level: :info
