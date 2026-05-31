# frozen_string_literal: true

# [REQ-FIT-BILL-001] Single-item shopping cart (guest or user-bound).
class Cart < ApplicationRecord
  belongs_to :nesting_run, optional: true
  belongs_to :user, optional: true

  enum :kind, { single_download: "single_download", plan: "plan" }, validate: true
  enum :currency_mode, { crc: "crc", usd: "usd" }, validate: true

  validate :must_have_guest_or_user
  validate :must_have_exactly_one_product_reference

  def tier_months_vo
    return nil if tier_months.blank?

    Billing::TierMonths.parse(tier_months)
  end

  def currency_vo
    Billing::Currency.parse(currency_mode)
  end

  private

  def must_have_guest_or_user
    has_guest = guest_token.present?
    has_user = user_id.present?
    return if has_guest || has_user

    errors.add(:base, "must have guest_token or user")
  end

  def must_have_exactly_one_product_reference
    has_run = nesting_run.present? || nesting_run_id.present?
    has_tier = tier_months.present?
    return if has_run ^ has_tier

    errors.add(:base, "must have exactly one of nesting_run or tier_months")
  end
end
