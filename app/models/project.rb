# frozen_string_literal: true

# [REQ-FIT-DOM-001] Nesting project with sheet inventory, layers, and job parameters.
# [REQ-FIT-AUTH-001] User-chosen 6-digit PIN stored as bcrypt digest.
class Project < ApplicationRecord
  has_many :sheet_stocks, -> { order(:sort_order) }, dependent: :destroy, inverse_of: :project

  accepts_nested_attributes_for :sheet_stocks, allow_destroy: true
  has_many :project_layers, dependent: :destroy, inverse_of: :project
  has_many :nesting_runs, dependent: :destroy, inverse_of: :project
  has_many_attached :input_dxf
  has_one_attached :nested_dxf
  has_one_attached :placements_json

  enum :status, {
    draft: "draft",
    ready: "ready",
    processing: "processing",
    completed: "completed",
    partial: "partial",
    failed: "failed"
  }, default: :draft, validate: true

  attr_reader :pin

  validates :title, presence: true
  validate :validate_pin_assignment

  before_validation :digest_pin, if: :digestible_pin?

  def pin=(value)
    @pin = value.to_s.presence
  end

  def authenticate_pin(candidate)
    return false if pin_digest.blank? || candidate.blank?

    BCrypt::Password.new(pin_digest) == candidate.to_s
  end

  def self.valid_pin_format?(value)
    value.to_s.match?(/\A\d{6}\z/)
  end

  private

  def digestible_pin?
    @pin.present? && self.class.valid_pin_format?(@pin)
  end

  def validate_pin_assignment
    return if @pin.blank?

    return if self.class.valid_pin_format?(@pin)

    errors.add(:pin, "must be exactly 6 digits")
  end

  def digest_pin
    self.pin_digest = BCrypt::Password.create(@pin)
    @pin = nil
  end
end
