# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Loads config/billing.yml; hot-reloads when mtime changes (D53).
  class Pricing
    CONFIG_PATH = Rails.root.join("config/billing.yml").freeze
    KEYS = %w[
      single_download_usd single_download_sinpe_crc single_download_official_crc
      single_download_overage_usd single_download_overage_sinpe_crc single_download_overage_official_crc
      single_download_official_usd single_download_sinpe_usd
      single_download_overage_official_usd single_download_overage_sinpe_usd
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

      # [REQ-FIT-BILL-001] Unified selector used by cart/checkout pricing.
      #
      # Preconditions:
      # - product must be supported
      # - currency and payment_method must be compatible
      # Postcondition:
      # - returns a positive numeric amount
      def price(product:, currency:, payment_method:, overage:)
        raise ArgumentError, "product must be a Symbol" unless product.is_a?(Symbol)
        raise ArgumentError, "currency must be :usd or :crc" unless %i[usd crc].include?(currency)
        raise ArgumentError, "payment_method must be :card or :sinpe" unless %i[card sinpe].include?(payment_method)
        raise ArgumentError, "overage must be boolean" unless overage == true || overage == false

        if currency == :crc && payment_method == :card
          key = price_key_for_official_crc(product:, overage:)
          amount = fetch(key)
          raise ArgumentError, "amount must be positive" unless amount.to_i.positive?
          return amount
        end

        if currency == :crc && payment_method == :sinpe
          key = price_key_for_sinpe_crc(product:, overage:)
          amount = fetch(key)
          raise ArgumentError, "amount must be positive" unless amount.to_i.positive?
          return amount
        end

        if currency == :usd && payment_method == :card
          key = price_key_for_official_usd(product:, overage:)
          amount = fetch(key)
          raise ArgumentError, "amount must be positive" unless amount.to_f.positive?
          return amount
        end

        raise ArgumentError, "unsupported currency/payment_method combination"
      end

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

      def price_key_for_official_crc(product:, overage:)
        case product
        when :single_download
          overage ? "single_download_overage_official_crc" : "single_download_official_crc"
        else
          raise ArgumentError, "unsupported product"
        end
      end

      def price_key_for_sinpe_crc(product:, overage:)
        case product
        when :single_download
          overage ? "single_download_overage_sinpe_crc" : "single_download_sinpe_crc"
        else
          raise ArgumentError, "unsupported product"
        end
      end

      def price_key_for_official_usd(product:, overage:)
        case product
        when :single_download
          overage ? "single_download_overage_official_usd" : "single_download_official_usd"
        else
          raise ArgumentError, "unsupported product"
        end
      end

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
