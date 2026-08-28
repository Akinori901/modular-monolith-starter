# frozen_string_literal: true

module Api
  # アーカイブされたログの参照。
  class LogsController < ApplicationController
    before_action :require_authentication!

    def index
      entries = Archiving::Api.recent(
        log_type: params.fetch(:log_type, Archiving::Api::AUDIT),
        owner_id: current_user_view.id,
        limit: params.fetch(:limit, 50).to_i.clamp(1, 200)
      )

      render json: { entries: entries.map(&:to_h) }
    rescue Archiving::Api::Error => e
      render json: { detail: e.message }, status: :bad_gateway
    end
  end
end
