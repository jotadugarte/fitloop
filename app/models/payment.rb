# frozen_string_literal: true

# [REQ-FIT-BILL-001] Payment record (simulate or ONVO gateway).
class Payment < ApplicationRecord
  belongs_to :user
  belongs_to :nesting_run, optional: true
  belongs_to :subscription, optional: true

  enum :status, { pending: "pending", succeeded: "succeeded", failed: "failed" }, validate: true
  enum :payment_method, { card_usd: "card_usd", card_crc: "card_crc", sinpe_crc: "sinpe_crc" }, validate: true
  enum :currency, { usd: "usd", crc: "crc" }, validate: true
  enum :purpose, { single_download: "single_download", plan_subscription: "plan_subscription" }, validate: true
  enum :gateway_provider, { onvo: "onvo" }, validate: { allow_nil: true }
  enum :onvo_mode, { test: "test", live: "live" }, validate: { allow_nil: true }

  ONVO_GATEWAY_SUCCEEDED = "succeeded"

  validates :amount, numericality: { greater_than: 0 }
  validates :paid_at, presence: true, if: :succeeded?
  validates :onvo_payment_intent_id, presence: true, if: :onvo_gateway?
  validates :onvo_mode, presence: true, if: :onvo_gateway?
  validates :gateway_status, presence: true, if: :onvo_gateway?
  validate :onvo_succeeded_requires_gateway_confirmation, if: :onvo_gateway?

  def onvo_gateway?
    gateway_provider == "onvo"
  end

  private

  def onvo_succeeded_requires_gateway_confirmation
    return unless succeeded?
    return if gateway_status == ONVO_GATEWAY_SUCCEEDED

    errors.add(:gateway_status, "must be succeeded for confirmed ONVO payment")
  end
end
