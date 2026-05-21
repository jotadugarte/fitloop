# frozen_string_literal: true

# [REQ-FIT-BILL-003] Download entitlement per nesting run (single purchase or plan).
class DownloadGrant < ApplicationRecord
  belongs_to :user
  belongs_to :nesting_run, optional: true

  has_one_attached :retained_nested_dxf

  enum :kind, { single_purchase: "single_purchase", plan_included: "plan_included" }, validate: true

  validates :nesting_run_id, uniqueness: { scope: :user_id }
  validates :retained_until, presence: true, if: :single_purchase?

  scope :retained_active, ->(at = Time.current) { single_purchase.where("retained_until > ?", at) }

  def retention_active?(at = Time.current)
    single_purchase? && retained_until.present? && retained_until >= at
  end

  def purge_retained_blob!
    retained_nested_dxf.purge if retained_nested_dxf.attached?
  end
end
