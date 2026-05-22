# frozen_string_literal: true

# [REQ-FIT-BILL-002] Monthly download quota counter (50 per calendar month, D27).
class PlanMonthlyUsage < ApplicationRecord
  DEFAULT_QUOTA = 50

  belongs_to :subscription

  attribute :quota_limit, :integer, default: DEFAULT_QUOTA
  attribute :downloads_used, :integer, default: 0

  validates :period_year, :period_month, presence: true
  validates :period_month, uniqueness: { scope: %i[subscription_id period_year] }
  validates :downloads_used, numericality: { greater_than_or_equal_to: 0, less_than_or_equal_to: :quota_limit }
  validates :quota_limit, numericality: { greater_than: 0 }
end
