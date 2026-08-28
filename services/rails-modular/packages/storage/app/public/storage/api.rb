# frozen_string_literal: true

module Storage
  # storage パッケージの**公開 API**。
  #
  # 他パッケージ・Controller から触ってよいのはこのクラスだけ。
  # S3Gateway は内部実装なので、外から参照すると packwerk が落とす。
  class Api
    Error = S3Gateway::StorageError

    # 保存したファイルの情報。S3 の生レスポンスを外へ出さない。
    StoredFile = Struct.new(:key, :size, :content_type, keyword_init: true) do
      def to_h = { key: key, size: size, content_type: content_type }
    end

    class << self
      # ファイルを保存する。
      #
      # キーは呼び出し側に決めさせず、ここで組み立てる。
      # 呼び出し側が自由に決めると、命名がバラバラになって後で移行できない。
      def upload(owner_id:, filename:, body:, content_type: "application/octet-stream")
        key = build_key(owner_id, filename)
        gateway.put(key: key, body: body, content_type: content_type)

        StoredFile.new(key: key, size: body.bytesize, content_type: content_type)
      end

      def download(key) = gateway.get(key)

      def delete(key) = gateway.delete(key)

      def presigned_url(key, expires_in: 900) = gateway.presigned_url(key, expires_in: expires_in)

      def ping = gateway.ping

      private

      def gateway = @gateway ||= S3Gateway.new

      # uploads/<owner>/<date>/<uuid>_<filename>
      #
      # 日付を挟むのは、S3 のプレフィックス分散とライフサイクルルールのため。
      # UUID を付けるのは同名ファイルの衝突を避けるため。
      def build_key(owner_id, filename)
        safe = File.basename(filename).gsub(/[^\w.\-]/, "_")
        "uploads/#{owner_id}/#{Time.current.strftime("%Y/%m/%d")}/#{SecureRandom.uuid}_#{safe}"
      end
    end
  end
end
