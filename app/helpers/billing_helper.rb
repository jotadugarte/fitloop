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

  # [REQ-FIT-BILL-001] Plan tiers for paywall/planes catalog (months, i18n key, card USD, SINPE CRC).
  def paywall_plan_tiers
    [
      [1, "tier_1", Billing::Pricing.plan_1_month_card_usd, Billing::Pricing.plan_1_month_sinpe_crc],
      [2, "tier_2", Billing::Pricing.plan_2_months_card_usd, Billing::Pricing.plan_2_months_sinpe_crc],
      [4, "tier_4", Billing::Pricing.plan_4_months_card_usd, Billing::Pricing.plan_4_months_sinpe_crc]
    ]
  end

  def format_billing_usd(amount)
    format("$%.2f", amount.to_f)
  end

  def format_billing_crc(amount)
    number_with_delimiter(amount.to_i, delimiter: ",")
      .then { |formatted| "₡#{formatted}" }
  end
end
