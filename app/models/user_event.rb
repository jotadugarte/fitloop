# frozen_string_literal: true

class UserEvent < ApplicationRecord
  belongs_to :user, optional: true

  validates :event_type, presence: true
  validates :occurred_at, presence: true
  validates :priority, presence: true, inclusion: { in: %w[low critical] }
  validates :idempotency_key, uniqueness: { allow_nil: true }

  attribute :properties, default: -> { {} }
end
