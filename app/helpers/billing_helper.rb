# frozen_string_literal: true

module BillingHelper
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
end
