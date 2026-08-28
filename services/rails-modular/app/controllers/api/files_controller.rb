# frozen_string_literal: true

module Api
  # S3 へのアップロードと、DynamoDB への操作ログ記録。
  #
  # **認証 → 保存 → アーカイブ**という流れを1本で示す。
  class FilesController < ApplicationController
    before_action :require_authentication!

    def create
      file = params.require(:file)

      stored = Storage::Api.upload(
        owner_id: current_user_view.id,
        filename: file.original_filename,
        body: file.read,
        content_type: file.content_type
      )

      # 操作ログは**非同期**。アップロード自体は既に成功しているので、
      # ログの書き込みで応答を待たせない。
      Archiving::Api.record_later(
        log_type: Archiving::Api::OPERATION,
        owner_id: current_user_view.id,
        payload: { event: "file_uploaded", key: stored.key, size: stored.size }
      )

      render json: stored.to_h, status: :created
    rescue ActionController::ParameterMissing => e
      render json: { detail: "#{e.param} は必須です" }, status: :bad_request
    rescue Storage::Api::Error => e
      render json: { detail: e.message }, status: :bad_gateway
    end

    def show
      # ファイル本体をアプリで中継しない。署名付き URL を返して
      # クライアントに直接 S3 を叩かせる（帯域と実行時間の節約）。
      render json: { url: Storage::Api.presigned_url(params.require(:key)) }
    end
  end
end
