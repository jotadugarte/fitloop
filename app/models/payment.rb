# frozen_string_literal: true

# [REQ-FIT-BILL-001] Simulated payment record (card USD / SINPE CRC).
class Payment < ApplicationRecord
  belongs_to :user
  belongs_to :nesting_run, optional: true
  belongs_to :subscription, optional: true

  enum :status, { pending: "pending", succeeded: "succeeded", failed: "failed" }, validate: true
  enum :payment_method, { card_usd: "card_usd", sinpe_crc: "sinpe_crc" }, validate: true
  enum :currency, { usd: "usd", crc: "crc" }, validate: true
  enum :purpose, { single_download: "single_download", plan_subscription: "plan_subscription" }, validate: true

  validates :amount, numericality: { greater_than: 0 }
  validates :paid_at, presence: true, unless: :pending?
end
