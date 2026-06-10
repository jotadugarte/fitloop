# frozen_string_literal: true

# [REQ-FIT-OPS-001] User-submitted product feedback (suggestion, bug report, other).
class Feedback < ApplicationRecord
  belongs_to :user, optional: true

  enum :feedback_type, { suggestion: "suggestion", bug: "bug", other: "other" }, validate: true
  enum :status, { pending: "pending", reviewed: "reviewed", archived: "archived" }, validate: true, default: :pending

  validates :message, presence: true, length: { minimum: Feedback::Message::MIN_LENGTH, maximum: Feedback::Message::MAX_LENGTH }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_nil: true
  validate :email_required_for_anonymous_submitter

  before_validation :normalize_email

  def submitter_email
    user&.email || email
  end

  def self.build_from_params(params:, user: nil, guest_context: nil)
    precondition!(params.is_a?(ActionController::Parameters) || params.is_a?(Hash))

    record = new(
      feedback_type: params[:feedback_type],
      message: params[:message],
      source_url: params[:source_url].to_s.presence,
      user: user
    )
    record.email = user.present? ? nil : params[:email].to_s.strip.downcase.presence
    record.guest_metadata = guest_context.to_h if guest_context.present? && user.blank?

    postcondition!(record.is_a?(Feedback))
    record
  end

  def self.precondition!(condition)
    raise ArgumentError, "precondition failed" unless condition
  end

  def self.postcondition!(condition)
    raise ArgumentError, "postcondition failed" unless condition
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase.presence
  end

  def email_required_for_anonymous_submitter
    return if user_id.present?
    return if email.present?

    errors.add(:email, :blank)
  end
end
