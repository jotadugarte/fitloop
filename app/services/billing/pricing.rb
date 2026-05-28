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
      plan_1_month_card_usd plan_1_month_official_crc plan_1_month_sinpe_crc plan_1_month_sinpe_usd
      plan_2_months_card_usd plan_2_months_official_crc plan_2_months_sinpe_crc plan_2_months_sinpe_usd
      plan_4_months_card_usd plan_4_months_official_crc plan_4_months_sinpe_crc plan_4_months_sinpe_usd
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
        fetch("single_download_overage_usd")
      end

      def single_download_overage_sinpe_crc
        fetch("single_download_overage_sinpe_crc")
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

      def has_key?(key)
        current_data.key?(key)
      end

      def current_data
        mtime = File.mtime(CONFIG_PATH)
        return @data if @mtime == mtime && @data

        @mtime = mtime
        @data = normalize_data(YAML.load_file(CONFIG_PATH))
      end

      def normalize_data(raw)
        raise ArgumentError, "billing.yml must be a Hash" unless raw.is_a?(Hash)
        return raw unless raw.key?("products")

        products = raw.fetch("products")
        raise ArgumentError, "billing.yml products must be a Hash" unless products.is_a?(Hash)

        normalized = raw.dup

        merge_product_prices!(normalized, products["single_download"], prefix: "single_download")
        merge_product_prices!(normalized, products["plan_1_month"], prefix: "plan_1_month", usd_card_key: "plan_1_month_card_usd")
        merge_product_prices!(normalized, products["plan_2_months"], prefix: "plan_2_months", usd_card_key: "plan_2_months_card_usd")
        merge_product_prices!(normalized, products["plan_4_months"], prefix: "plan_4_months", usd_card_key: "plan_4_months_card_usd")

        normalized
      end

      def merge_product_prices!(normalized, product, prefix:, usd_card_key: nil)
        return unless product

        normalized["#{prefix}_official_crc"] = dig_required(product, %w[official crc])
        normalized["#{prefix}_sinpe_crc"] = dig_required(product, %w[sinpe crc])
        normalized["#{prefix}_official_usd"] = dig_required(product, %w[official usd])
        normalized["#{prefix}_sinpe_usd"] = dig_required(product, %w[sinpe usd])
        normalized[usd_card_key || "#{prefix}_official_usd"] = dig_required(product, %w[official usd])

        return unless product.key?("overage")

        normalized["#{prefix}_overage_official_crc"] = dig_required(product, %w[overage official crc])
        normalized["#{prefix}_overage_sinpe_crc"] = dig_required(product, %w[overage sinpe crc])
        normalized["#{prefix}_overage_official_usd"] = dig_required(product, %w[overage official usd])
        normalized["#{prefix}_overage_sinpe_usd"] = dig_required(product, %w[overage sinpe usd])
      end

      def dig_required(hash, path)
        current = hash
        path.each do |segment|
          raise ArgumentError, "billing.yml missing #{path.join('.')}" unless current.is_a?(Hash) && current.key?(segment)
          current = current.fetch(segment)
        end
        current
      end
    end
  end
end
