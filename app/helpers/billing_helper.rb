# frozen_string_literal: true

module BillingHelper
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
