# frozen_string_literal: true

# [REQ-FIT-BILL-002] Plan subscription (1, 2, or 4 months).
class Subscription < ApplicationRecord
  ALLOWED_TIER_MONTHS = [ 1, 2, 4 ].freeze

  belongs_to :user
  has_many :plan_monthly_usages, dependent: :destroy
  has_many :payments, dependent: :nullify

  validates :tier_months, inclusion: { in: ALLOWED_TIER_MONTHS }
  validates :starts_at, presence: true
  validates :ends_at, comparison: { greater_than: :starts_at }

  scope :active_at, ->(time = Time.current) { where("starts_at <= ? AND ends_at >= ?", time, time) }

  def active_at?(time = Time.current)
    starts_at <= time && ends_at >= time
  end
end
