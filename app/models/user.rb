# frozen_string_literal: true

# [REQ-FIT-AUTH-002] Persistent user identity; projects remain ephemeral (ADR-0005).
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :validatable, :confirmable,
         :omniauthable, omniauth_providers: %i[google_oauth2 facebook apple]

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

  def self.from_omniauth(auth, time_zone: nil)
    precondition!(auth.info.email.present?)

    user = find_or_initialize_by(provider: auth.provider.to_s, uid: auth.uid.to_s)
    user.email = auth.info.email
    user.name = auth.info.name.presence || user.email.to_s.split("@").first
    user.time_zone = time_zone.presence || "America/Costa_Rica"
    user.terms_accepted_at ||= Time.current
    user.terms_version ||= TermsVersion.current
    user.password = Devise.friendly_token[32] if user.new_record?
    user.confirmed_at ||= Time.current if trusted_oauth_provider?(auth.provider)
    user.save!
    user
  end

  def self.trusted_oauth_provider?(provider)
    %w[google_oauth2 facebook apple].include?(provider.to_s)
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

  def precondition!(condition)
    raise ArgumentError, "precondition failed" unless condition
  end
end
