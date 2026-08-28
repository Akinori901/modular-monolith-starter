# frozen_string_literal: true

module Api
  class HealthController < ApplicationController
    # 各依存の疎通確認。1つ落ちても残りは確認する
    # （全体像が見えないと切り分けができない）。
    CHECKS = {
      "database" => -> { ActiveRecord::Base.connection.execute("SELECT 1") },
      "object_storage" => -> { Storage::Api.ping },
      "cognito" => -> { Identity::Api.ping },
      "log_archive" => -> { Archiving::Api.ping }
    }.freeze

    def show
      components = CHECKS.map { |name, check| probe(name, &check) }
      healthy = components.all? { |c| c[:state] == "up" }

      # 依存が落ちていれば 503。ALB はステータスコードで判定するため、
      # 本文が返せていても 200 にしないこと。
      render json: { healthy: healthy, components: components },
        status: healthy ? :ok : :service_unavailable
    end

    # プロセスの生存のみを見る（依存を確認しない）
    def live = render(json: { status: "ok" })

    private

    def probe(name)
      yield
      { name: name, state: "up", detail: "" }
    rescue StandardError => e
      { name: name, state: "down", detail: e.message.truncate(200) }
    end
  end
end
