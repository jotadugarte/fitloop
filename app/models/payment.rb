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

  scope :listed_in_payment_history, -> { where(checkout_abandoned_at: nil) }

  validates :amount, numericality: { greater_than: 0 }
  validates :paid_at, presence: true, if: :succeeded?
  validates :onvo_payment_intent_id, presence: true, if: :onvo_gateway?
  validates :onvo_mode, presence: true, if: :onvo_gateway?
  validates :gateway_status, presence: true, if: :onvo_gateway?
  validates :purchase_reference,
            format: { with: /\A\d{12}\z/ },
            allow_nil: true,
            uniqueness: true
  validate :onvo_succeeded_requires_gateway_confirmation, if: :onvo_gateway?

  before_create :assign_purchase_reference_for_single_download

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

  def checkout_abandoned?
    checkout_abandoned_at.present?
  end

  # SINPE manual abandon keeps polling/rows (transfer may still complete).
  # Card 3DS cancel hides the attempt from Mis pagos rows and payment history.
  def awaiting_gateway_confirmation?
    return false unless pending? && single_download?
    return false if superseded?
    return false if checkout_abandoned? && card_checkout?

    !downloadable_grant_for_run?
  end

  def superseded?
    superseded_at.present?
  end

  def sinpe_awaiting_transfer?
    sinpe_crc? && pending? && gateway_status.to_s == "processing"
  end

  def sinpe_checkout_resumable?
    sinpe_crc? && pending? && !superseded?
  end

  def downloadable_grant_for_run?
    return false if nesting_run_id.blank?

    grant = DownloadGrant.find_by(user_id: user_id, nesting_run_id: nesting_run_id)
    return false if grant.nil?

    grant.retention_active? && grant.updated_at >= created_at
  end

  def incomplete_card_checkout_attempt?
    return false unless card_checkout?
    return false if succeeded?
    return true if superseded_by_later_successful_checkout?
    return false unless pending? || failed?

    !downloadable_grant_for_run?
  end

  def superseded_by_later_successful_checkout?
    return false if nesting_run_id.blank?

    Payment.succeeded.single_download
           .where(user_id: user_id, nesting_run_id: nesting_run_id)
           .where("created_at > ?", created_at)
           .exists?
  end

  def onvo_succeeded_requires_gateway_confirmation
    return unless succeeded?
    return if gateway_status == ONVO_GATEWAY_SUCCEEDED

    errors.add(:gateway_status, "must be succeeded for confirmed ONVO payment")
  end

  def assign_purchase_reference_for_single_download
    return unless single_download?
    return if purchase_reference.present?

    self.purchase_reference = Billing::PurchaseReference.generate
  end

  def card_checkout?
    card_crc? || card_usd?
  end

  private :assign_purchase_reference_for_single_download, :card_checkout?
end
