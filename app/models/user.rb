# frozen_string_literal: true

# [REQ-FIT-AUTH-002] Persistent user identity; projects remain ephemeral (ADR-0005).
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :validatable, :confirmable

  alias_attribute :email_confirmed_at, :confirmed_at

  before_validation :normalize_email

  validates :name, presence: true
  validates :terms_accepted_at, presence: true
  validates :terms_version, presence: true
  validates :time_zone, presence: true
  validates :email, uniqueness: { case_sensitive: false }
  validate :password_minimum_length, if: :password_required?

  def billing_ready?
    precondition!(persisted?)
    email_confirmed_at.present?
  end

  def operationally_active?
    precondition!(persisted?)
    suspended_at.nil?
  end

  def send_on_create_confirmation_instructions
    return if Rails.env.test?

    super
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def password_minimum_length
    return if password.blank?
    return if password.length >= 12

    errors.add(:password, "must be at least 12 characters")
  end

  def password_required?
    !persisted? || password.present? || password_confirmation.present?
  end

  def precondition!(condition)
    raise ArgumentError, "precondition failed" unless condition
  end
end
