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

  # [REQ-FIT-BILL-001] SINPE pending checkout workshop lock (see PendingCheckoutPolicy).
  def checkout_lock_active?
    return false unless sinpe_crc? && pending?
    return false if superseded?
    return false if checkout_lock_released_at.present?
    return false if checkout_abandoned_at.present?
    return false if downloadable_grant_for_run?

    Billing::PendingCheckoutPolicy.lock_active?(self)
  end

  def checkout_lock_expired?
    return false unless sinpe_crc? && pending?

    Time.current >= Billing::PendingCheckoutPolicy.lock_expires_at(self)
  end

  def awaiting_gateway_confirmation?
    return false unless pending? && single_download?
    return false if superseded?

    !downloadable_grant_for_run?
  end

  def superseded?
    superseded_at.present?
  end

  private

  def downloadable_grant_for_run?
    return false if nesting_run_id.blank?

    grant = DownloadGrant.find_by(user_id: user_id, nesting_run_id: nesting_run_id)
    grant&.retention_active?
  end

  def onvo_succeeded_requires_gateway_confirmation
    return unless succeeded?
    return if gateway_status == ONVO_GATEWAY_SUCCEEDED

    errors.add(:gateway_status, "must be succeeded for confirmed ONVO payment")
  end
end
