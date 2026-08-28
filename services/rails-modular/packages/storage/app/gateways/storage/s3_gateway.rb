# frozen_string_literal: true

require "aws-sdk-s3"

module Storage
  # S3（本番）/ SeaweedFS（ローカル）とのやり取りを閉じ込める。
  #
  # endpoint を差し替えるだけで両方に対応する。
  # S3 互換 API を使う限り、コードは共通で済む。
  class S3Gateway
    class StorageError < StandardError; end

    def initialize(config = Rails.application.config.x.s3)
      @bucket = config.bucket
      @client = Aws::S3::Client.new(
        **{ region: config.region }.tap { |o|
          if config.endpoint.present?
            o[:endpoint] = config.endpoint
            # SeaweedFS 等の S3 互換実装は仮想ホスト形式に対応しないことがある
            o[:force_path_style] = true
          end
        }
      )
    end

    # @return [String] 保存したキー
    def put(key:, body:, content_type: "application/octet-stream")
      @client.put_object(bucket: @bucket, key: key, body: body, content_type: content_type)
      key
    rescue Aws::S3::Errors::ServiceError => e
      raise StorageError, "アップロードに失敗しました: #{e.message}"
    end

    def get(key)
      @client.get_object(bucket: @bucket, key: key).body.read
    rescue Aws::S3::Errors::NoSuchKey
      nil
    rescue Aws::S3::Errors::ServiceError => e
      raise StorageError, "取得に失敗しました: #{e.message}"
    end

    def delete(key)
      @client.delete_object(bucket: @bucket, key: key)
      nil
    end

    # 署名付き URL。**ファイル本体をアプリで中継しない**ための仕組み。
    # 中継すると Lambda のメモリと実行時間を無駄に食う。
    def presigned_url(key, expires_in: 900)
      Aws::S3::Presigner.new(client: @client)
        .presigned_url(:get_object, bucket: @bucket, key: key, expires_in: expires_in)
    end

    # 疎通確認。オブジェクト一覧ではなく head_bucket を使う。
    # 必要な権限が最小で済み、バケットの中身の量に影響されない。
    def ping
      @client.head_bucket(bucket: @bucket)
      nil
    end
  end
end
