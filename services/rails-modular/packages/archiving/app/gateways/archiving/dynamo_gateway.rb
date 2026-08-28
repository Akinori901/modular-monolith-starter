# frozen_string_literal: true

require "aws-sdk-dynamodb"

module Archiving
  # DynamoDB とのやり取りを閉じ込める。
  #
  # テーブル設計:
  #   PK = "<log_type>#<owner_id>"   例: "audit#user-123"
  #   SK = "<ISO8601 timestamp>#<uuid>"
  #
  # **時系列で引けることを優先した設計。**
  # 「あるユーザーの直近のログ」が SK の範囲検索だけで取れる。
  # GSI を足さずに済むぶん、書き込みコストも低い。
  #
  # TTL 属性(expires_at)を付けており、保持期間を過ぎたものは
  # DynamoDB 側が自動削除する（削除のためのバッチを書かない）。
  class DynamoGateway
    class ArchiveError < StandardError; end

    def initialize(config = Rails.application.config.x.dynamodb)
      @table = config.table
      @retention = config.retention_days.to_i
      @client = Aws::DynamoDB::Client.new(
        **{ region: config.region }.tap { |o|
          o[:endpoint] = config.endpoint if config.endpoint.present?
        }
      )
    end

    def put(log_type:, owner_id:, payload:, occurred_at: Time.current)
      item = {
        "pk" => "#{log_type}##{owner_id}",
        "sk" => "#{occurred_at.utc.iso8601(6)}##{SecureRandom.uuid}",
        "log_type" => log_type.to_s,
        "owner_id" => owner_id.to_s,
        "occurred_at" => occurred_at.utc.iso8601(6),
        # TTL。保持期間を過ぎたら DynamoDB が勝手に消す。
        "expires_at" => (occurred_at + @retention.days).to_i,
        "payload" => stringify(payload)
      }

      @client.put_item(table_name: @table, item: item)
      item["sk"]
    rescue Aws::DynamoDB::Errors::ServiceError => e
      raise ArchiveError, "アーカイブに失敗しました: #{e.message}"
    end

    # 直近のログを新しい順に返す。
    def query(log_type:, owner_id:, limit: 50, since: nil)
      params = {
        table_name: @table,
        key_condition_expression: "pk = :pk",
        expression_attribute_values: { ":pk" => "#{log_type}##{owner_id}" },
        # 新しい順（SK の降順）
        scan_index_forward: false,
        limit: limit
      }

      if since
        params[:key_condition_expression] += " AND sk >= :since"
        params[:expression_attribute_values][":since"] = since.utc.iso8601(6)
      end

      @client.query(**params).items
    rescue Aws::DynamoDB::Errors::ServiceError => e
      raise ArchiveError, "検索に失敗しました: #{e.message}"
    end

    # 疎通確認
    def ping
      @client.describe_table(table_name: @table)
      nil
    end

    private

    # DynamoDB は数値・真偽値をそのまま扱えるが、payload の形が
    # 呼び出し側でまちまちになるため、値は文字列へ寄せて安定させる。
    def stringify(payload)
      payload.compact.transform_keys(&:to_s).transform_values(&:to_s)
    end
  end
end
