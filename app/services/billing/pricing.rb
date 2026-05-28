# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Loads config/billing.yml; hot-reloads when mtime changes (D53).
  class Pricing
    CONFIG_PATH = Rails.root.join("config/billing.yml").freeze
    KEYS = %w[
      single_download_usd single_download_sinpe_crc single_download_official_crc
      single_download_overage_usd single_download_overage_sinpe_crc single_download_overage_official_crc
      plan_quota_overage_percent
      plan_1_month_card_usd plan_1_month_sinpe_crc plan_2_months_card_usd plan_2_months_sinpe_crc
      plan_4_months_card_usd plan_4_months_sinpe_crc
    ].freeze

    class << self
      def reset_cache!
        @mtime = nil
        @data = nil
      end

      KEYS.each { |key| define_method(key) { fetch(key) } }

      def single_download_overage_usd
        return fetch("single_download_overage_usd") if has_key?("single_download_overage_usd")

        overage_amount(fetch("single_download_usd").to_f)
      end

      def single_download_overage_sinpe_crc
        return fetch("single_download_overage_sinpe_crc") if has_key?("single_download_overage_sinpe_crc")

        overage_amount(fetch("single_download_sinpe_crc").to_i).to_i
      end

      def single_download_overage_official_crc
        fetch("single_download_overage_official_crc")
      end

      private

      def fetch(key)
        value = current_data.fetch(key)
        raise ArgumentError, "#{key} must be positive" unless value.to_f.positive?

        key.end_with?("_usd") ? value.to_f : value.to_i
      end

      def overage_amount(base)
        (base * fetch("plan_quota_overage_percent") / 100.0).round(2)
      end

      def has_key?(key)
        current_data.key?(key)
      end

      def current_data
        mtime = File.mtime(CONFIG_PATH)
        return @data if @mtime == mtime && @data

        @mtime = mtime
        @data = YAML.load_file(CONFIG_PATH)
      end
    end
  end
end
