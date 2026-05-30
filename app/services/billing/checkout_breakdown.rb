# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] Line-item breakdown for cart/checkout (IVA only in CR).
  class CheckoutBreakdown
    class << self
      def for_cart(cart:, billing_context:)
        raise ArgumentError, "cart required" if cart.nil?

        ctx = resolve_context(billing_context)
        list_cents = cart.list_price_cents.to_i
        sinpe_cents = cart.sinpe_price_cents.to_i
        build(
          list_amount: cents_to_amount(list_cents, ctx.currency),
          sinpe_amount: cents_to_amount(sinpe_cents, ctx.currency),
          context: ctx
        )
      end

      def for_plan(tier_months:, billing_context:)
        ctx = resolve_context(billing_context)
        tier = tier_months.is_a?(TierMonths) ? tier_months : TierMonths.parse(tier_months)
        list_price, sinpe_price = plan_list_and_sinpe(currency: ctx.currency, tier_months: tier)

        build(
          list_amount: list_price,
          sinpe_amount: sinpe_price,
          context: ctx
        )
      end

      def for_single_download(billing_context:, overage: false)
        ctx = resolve_context(billing_context)
        list_price = Pricing.price(product: :single_download, currency: ctx.currency, payment_method: BillingMethod.parse(:card), overage: overage)
        sinpe_price = sinpe_reference_price(currency: ctx.currency, overage: overage)

        build(
          list_amount: list_price,
          sinpe_amount: sinpe_price,
          context: ctx
        )
      end

      private

      def resolve_context(billing_context)
        return billing_context if billing_context.is_a?(CheckoutContext)

        CheckoutContext.from_session(billing_context)
      end

      def plan_list_and_sinpe(currency:, tier_months:)
        card_usd, official_crc, sinpe_crc = Pricing.plan_price_triple(tier_months)
        if currency.to_sym == :usd
          [card_usd, card_usd]
        else
          [official_crc, sinpe_crc]
        end
      end

      def sinpe_reference_price(currency:, overage:)
        curr = currency.is_a?(Currency) ? currency : Currency.parse(currency)
        return nil unless curr.crc?

        Pricing.price(product: :single_download, currency: curr, payment_method: BillingMethod.parse(:sinpe), overage: overage)
      end

      def build(list_amount:, sinpe_amount:, context:)
        list = Money.from_major(list_amount, context.currency)
        sinpe = sinpe_amount.nil? ? nil : Money.from_major(sinpe_amount, context.currency)
        sinpe_discount = compute_sinpe_discount(list, sinpe, context.payment_method)
        net_subtotal = Money.from_major(list.amount - sinpe_discount, context.currency)
        tax = compute_tax(net_subtotal, context.iva_applicable)
        total = net_subtotal + tax

        {
          currency: context.currency.to_sym,
          payment_method: context.payment_method.to_sym,
          iva_applicable: context.iva_applicable,
          list_price: list.amount,
          discount_amount: sinpe_discount,
          subtotal: net_subtotal.amount,
          tax_amount: tax.amount,
          total_amount: total.amount
        }
      end

      def compute_sinpe_discount(list, sinpe, payment_method)
        return 0 unless payment_method.sinpe? && sinpe

        [list.amount - sinpe.amount, 0].max
      end

      def compute_tax(net_subtotal, iva_applicable)
        return Money.from_major(0, net_subtotal.currency) unless iva_applicable

        tax_amount = (net_subtotal.amount * RegionalPolicy::IVA_RATE).round(2)
        Money.from_major(tax_amount, net_subtotal.currency)
      end

      def cents_to_amount(cents, currency)
        curr = currency.is_a?(Currency) ? currency : Currency.parse(currency)
        curr.crc? ? cents : (cents / 100.0)
      end
    end
  end
end
