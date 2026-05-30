# frozen_string_literal: true

# [REQ-FIT-BILL-003] Download entitlement per nesting run (single purchase or plan).
#
# Single-purchase retention: SINPE pre-retention may copy the nested DXF with
# retained_until nil (staging — not downloadable until FulfillPayment sets the 24h window).
class DownloadGrant < ApplicationRecord
  belongs_to :user
  belongs_to :nesting_run, optional: true

  has_one_attached :retained_nested_dxf

  attr_accessor :retention_committed

  enum :kind, { single_purchase: "single_purchase", plan_included: "plan_included" }, validate: true

  validates :nesting_run_id, uniqueness: { scope: :user_id }
  validates :retained_until, presence: true, if: :require_retained_until?

  scope :retained_active, ->(at = Time.current) { single_purchase.where("retained_until > ?", at) }

  def retention_active?(at = Time.current)
    single_purchase? && retained_until.present? && retained_until >= at
  end

  def purge_retained_blob!
    retained_nested_dxf.purge if retained_nested_dxf.attached?
  end

  def retention_committed?
    return true if ActiveModel::Type::Boolean.new.cast(retention_committed)

    single_purchase? && persisted? && retained_until_in_database.present?
  end

  private

  def require_retained_until?
    return false unless single_purchase?
    return true if retention_committed?

    retained_until.present?
  end
end
