# frozen_string_literal: true

# パッケージ間のイベント購読を設定する。
#
# **依存の向きを反転させるための仕組み。**
# identity は archiving を知らないまま、archiving 側が
# identity のイベントを購読する。
Rails.application.config.after_initialize do
  Archiving::IdentityEventSubscriber.subscribe!
end
