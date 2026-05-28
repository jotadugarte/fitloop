# frozen_string_literal: true

module BillingHelper
  include ActionView::Helpers::NumberHelper
  # [REQ-FIT-BILL-002] Show instants in the user's time zone (D29); avoids UTC 05:59 for CR 23:59.
  def l_in_user_zone(time, format:, user: current_user)
    return "" if time.blank?

    zone = user&.time_zone.presence || Time.zone.name
    I18n.l(time.in_time_zone(zone), format: format)
  end

  def plan_tier_label(tier_months)
    key = { 1 => "tier_1", 2 => "tier_2", 4 => "tier_4" }.fetch(tier_months.to_i) do
      raise ArgumentError, "unknown plan tier_months: #{tier_months}"
    end
    t("billing.planes.#{key}")
  end

  def payment_status_badge_class(status)
    case status.to_s
    when "succeeded" then "status-badge--completed"
    when "failed" then "status-badge--failed"
    else "status-badge--draft"
    end
  end

  # [REQ-FIT-BILL-001] Plan tiers for paywall catalog (months, i18n key).
  def paywall_plan_tiers
    [
      [1, "tier_1"],
      [2, "tier_2"],
      [4, "tier_4"]
    ]
  end

  # [REQ-FIT-BILL-001] MEIC-aware price block for paywall cards (D25).
  #
  # Returns { primary_label:, primary_amount:, reference_label:, reference_amount: }.
  # reference_* is nil when not shown (USD abroad, or CRC without SINPE).
  def paywall_price_display(product:, currency:, show_sinpe:, tier_months: nil)
    case product
    when :single_download
      paywall_single_download_price_display(currency:, show_sinpe:)
    when :plan
      paywall_plan_price_display(tier_months:, currency:, show_sinpe:)
    else
      raise ArgumentError, "unsupported product: #{product}"
    end
  end

  def format_billing_usd(amount)
    format("$%.2f", amount.to_f)
  end

  def format_billing_crc(amount)
    number_with_delimiter(amount.to_i, delimiter: ",")
      .then { |formatted| "₡#{formatted}" }
  end

  private

  def paywall_single_download_price_display(currency:, show_sinpe:)
    if currency == :usd
      return {
        primary_label: t("billing.checkout.card_usd"),
        primary_amount: format_billing_usd(Billing::Pricing.single_download_official_usd),
        reference_label: nil,
        reference_amount: nil
      }
    end

    if show_sinpe
      {
        primary_label: t("billing.checkout.sinpe_crc"),
        primary_amount: format_billing_crc(Billing::Pricing.single_download_sinpe_crc),
        reference_label: t("billing.paywall.card_crc_reference"),
        reference_amount: format_billing_crc(Billing::Pricing.single_download_official_crc)
      }
    else
      {
        primary_label: t("billing.paywall.card_crc"),
        primary_amount: format_billing_crc(Billing::Pricing.single_download_official_crc),
        reference_label: nil,
        reference_amount: nil
      }
    end
  end

  def paywall_plan_price_display(tier_months:, currency:, show_sinpe:)
    card_usd, official_crc, sinpe_crc = plan_price_triple(tier_months)

    if currency == :usd
      return {
        primary_label: t("billing.checkout.card_usd"),
        primary_amount: format_billing_usd(card_usd),
        reference_label: nil,
        reference_amount: nil
      }
    end

    if show_sinpe
      {
        primary_label: t("billing.checkout.sinpe_crc"),
        primary_amount: format_billing_crc(sinpe_crc),
        reference_label: t("billing.paywall.card_crc_reference"),
        reference_amount: format_billing_crc(official_crc)
      }
    else
      {
        primary_label: t("billing.paywall.card_crc"),
        primary_amount: format_billing_crc(official_crc),
        reference_label: nil,
        reference_amount: nil
      }
    end
  end

  def plan_price_triple(tier_months)
    case tier_months.to_i
    when 1
      [Billing::Pricing.plan_1_month_card_usd, Billing::Pricing.plan_1_month_official_crc, Billing::Pricing.plan_1_month_sinpe_crc]
    when 2
      [Billing::Pricing.plan_2_months_card_usd, Billing::Pricing.plan_2_months_official_crc, Billing::Pricing.plan_2_months_sinpe_crc]
    when 4
      [Billing::Pricing.plan_4_months_card_usd, Billing::Pricing.plan_4_months_official_crc, Billing::Pricing.plan_4_months_sinpe_crc]
    else
      raise ArgumentError, "unknown plan tier_months: #{tier_months}"
    end
  end
end
