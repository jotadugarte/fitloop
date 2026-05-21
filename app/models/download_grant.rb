# frozen_string_literal: true

# [REQ-FIT-BILL-003] Download entitlement per nesting run (single purchase or plan).
class DownloadGrant < ApplicationRecord
  belongs_to :user
  belongs_to :nesting_run

  has_one_attached :retained_nested_dxf

  enum :kind, { single_purchase: "single_purchase", plan_included: "plan_included" }, validate: true

  validates :nesting_run_id, uniqueness: { scope: :user_id }
  validates :retained_until, presence: true, if: :single_purchase?
end
