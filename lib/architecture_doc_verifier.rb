# frozen_string_literal: true

# Validates docs/core/SYSTEM_ARCHITECTURE.md against Fitloop stack anchors.
class ArchitectureDocVerifier
  DOC_PATH = File.expand_path("../docs/core/SYSTEM_ARCHITECTURE.md", __dir__)

  REQUIRED_STACK = [
    "Rails 8",
    "Hotwire",
    "PostgreSQL",
    "Solid Queue",
    "Active Storage"
  ].freeze

  REQUIRED_FORBIDDEN = [
    /nesting math.*Ruby/i,
    /Rails does not perform nesting/i
  ].freeze

  def self.verify!
    new.verify!
  end

  def verify!
    content = File.read(DOC_PATH)
    errors = []
    REQUIRED_STACK.each do |term|
      errors << "missing required stack term: #{term}" unless content.include?(term)
    end
    unless REQUIRED_FORBIDDEN.any? { |pattern| content.match?(pattern) }
      errors << "missing kill-list rule: nesting math must not run in Ruby"
    end
    raise ArchitectureDocError, errors.join("; ") if errors.any?

    true
  end
end

class ArchitectureDocError < StandardError; end
