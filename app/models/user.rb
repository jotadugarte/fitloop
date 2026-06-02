# frozen_string_literal: true

# [REQ-FIT-AUTH-002] Persistent user identity; projects remain ephemeral (ADR-0005).
# [REQ-FIT-ADMIN-001] admin: boolean column — promoted via FITLOOP_ADMIN_EMAILS initializer.
# ActiveRecord generates admin? automatically. Never set via user registration flow.
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :validatable, :confirmable

  alias_attribute :email_confirmed_at, :confirmed_at

  has_many :subscriptions, dependent: :destroy
  has_many :payments, dependent: :destroy
  has_many :download_grants, dependent: :destroy
  has_many :user_events, dependent: :nullify

  before_validation :normalize_email

  validates :name, presence: true
  validates :terms_accepted_at, presence: true
  validates :terms_version, presence: true
  validates :time_zone, presence: true
  validates :email, uniqueness: { case_sensitive: false }
  validate :password_minimum_length, if: :password_required?

  def billing_ready?
    self.class.precondition!(persisted?)
    email_confirmed_at.present?
  end

  def operationally_active?
    self.class.precondition!(persisted?)
    suspended_at.nil?
  end

  def active_plan?(at: Time.current)
    Subscription.active_at(at).exists?(user_id: id)
  end



  private

  def self.precondition!(condition)
    raise ArgumentError, "precondition failed" unless condition
  end

  def normalize_email
    self.email = email.to_s.strip.downcase
  end

  def password_minimum_length
    return if password.blank?
    return if password.length >= 12

    errors.add(:password, "must be at least 12 characters")
  end

  def password_required?
    return false if provider.present?

    !persisted? || password.present? || password_confirmation.present?
  end
end
