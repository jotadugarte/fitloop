# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Line-item breakdown for cart/checkout (IVA only in CR).
  class CheckoutBreakdown
    class << self
      def for_cart(cart:, billing_context:)
        raise ArgumentError, "cart required" if cart.nil?

        list_cents = cart.list_price_cents.to_i
        sinpe_cents = cart.sinpe_price_cents.to_i
        build(
          list_amount: cents_to_amount(list_cents, billing_context.fetch(:currency)),
          sinpe_amount: cents_to_amount(sinpe_cents, billing_context.fetch(:currency)),
          currency: billing_context.fetch(:currency),
          payment_method: billing_context.fetch(:payment_method),
          iva_applicable: billing_context.fetch(:iva_applicable)
        )
      end

      def for_plan(tier_months:, billing_context:)
        currency = billing_context.fetch(:currency)
        payment_method = billing_context.fetch(:payment_method)
        list_price, sinpe_price = plan_list_and_sinpe(currency:, tier_months: tier_months)

        build(
          list_amount: list_price,
          sinpe_amount: sinpe_price,
          currency: currency,
          payment_method: payment_method,
          iva_applicable: billing_context.fetch(:iva_applicable)
        )
      end

      def for_single_download(billing_context:, overage: false)
        currency = billing_context.fetch(:currency)
        payment_method = billing_context.fetch(:payment_method)
        list_price = Pricing.price(product: :single_download, currency: currency, payment_method: :card, overage: overage)
        sinpe_price = sinpe_reference_price(currency: currency, overage: overage)

        build(
          list_amount: list_price,
          sinpe_amount: sinpe_price,
          currency: currency,
          payment_method: payment_method,
          iva_applicable: billing_context.fetch(:iva_applicable)
        )
      end

      private

      def plan_list_and_sinpe(currency:, tier_months:)
        card_usd, official_crc, sinpe_crc = plan_price_triple(tier_months)
        if currency == :usd
          [card_usd, card_usd]
        else
          [official_crc, sinpe_crc]
        end
      end

      def plan_price_triple(tier_months)
        case tier_months.to_i
        when 1
          [Pricing.plan_1_month_card_usd, Pricing.plan_1_month_official_crc, Pricing.plan_1_month_sinpe_crc]
        when 2
          [Pricing.plan_2_months_card_usd, Pricing.plan_2_months_official_crc, Pricing.plan_2_months_sinpe_crc]
        when 4
          [Pricing.plan_4_months_card_usd, Pricing.plan_4_months_official_crc, Pricing.plan_4_months_sinpe_crc]
        else
          raise ArgumentError, "unknown plan tier_months: #{tier_months}"
        end
      end

      def sinpe_reference_price(currency:, overage:)
        return nil unless currency == :crc

        Pricing.price(product: :single_download, currency: :crc, payment_method: :sinpe, overage: overage)
      end

      def build(list_amount:, sinpe_amount:, currency:, payment_method:, iva_applicable:)
        list = decimal(list_amount)
        sinpe_discount = payment_method == :sinpe && sinpe_amount ? [list - decimal(sinpe_amount), 0].max : 0
        net_subtotal = list - sinpe_discount
        tax = iva_applicable ? (net_subtotal * RegionalPolicy::IVA_RATE).round(2) : 0
        total = net_subtotal + tax

        {
          currency: currency,
          payment_method: payment_method,
          iva_applicable: iva_applicable,
          list_price: list,
          discount_amount: sinpe_discount,
          subtotal: net_subtotal,
          tax_amount: tax,
          total_amount: total
        }
      end

      def cents_to_amount(cents, currency)
        currency == :crc ? cents : (cents / 100.0)
      end

      def decimal(value)
        BigDecimal(value.to_s)
      end
    end
  end
end
