# frozen_string_literal: true

# Validates docs/core/SPEC.md against Fitloop MVP requirements (P0 step 2).
class SpecDocVerifier
  DOC_PATH = File.expand_path("../docs/core/SPEC.md", __dir__)

  TEMPLATE_MARKERS = [
    "[A high-level summary",
    "| Example |",
    "**Entity A**",
    "**Workflow X**"
  ].freeze

  REQUIRED_ENTITIES = %w[Project SheetStock ProjectLayer NestingRun].freeze

  REQUIRED_REQ_IDS = [
    "REQ-FIT-AUTH-001",
    "REQ-FIT-DOM-001",
    "REQ-FIT-DXF-001",
    "REQ-FIT-NEST-003",
    "REQ-FIT-CLI-001"
  ].freeze

  NESTING_STATUSES = %w[completed partial failed].freeze

  REQUIRED_SECTIONS = [
    "## Purpose",
    "## Domain Glossary",
    "## Core Entities",
    "## Requirements Traceability",
    "## CLI Contract"
  ].freeze

  def self.verify!
    new.verify!
  end

  def verify!
    content = File.read(DOC_PATH)
    errors = []

    TEMPLATE_MARKERS.each do |marker|
      errors << "template placeholder still present: #{marker}" if content.include?(marker)
    end

    REQUIRED_SECTIONS.each do |heading|
      errors << "missing section: #{heading}" unless content.include?(heading)
    end

    REQUIRED_ENTITIES.each do |entity|
      errors << "missing entity: #{entity}" unless content.match?(/\b#{entity}\b/)
    end

    REQUIRED_REQ_IDS.each do |req_id|
      errors << "missing requirement id: #{req_id}" unless content.include?(req_id)
    end

    NESTING_STATUSES.each do |status|
      errors << "missing nesting status: #{status}" unless content.match?(/\b#{status}\b/)
    end

    errors << "missing workspace session access (REQ-FIT-AUTH-001)" unless content.match?(/Workspace\.resolve!|workspace_project_id|ephemeral session/i)
    errors << "missing sheet inventory (finite or infinite quantity)" unless content.match?(/SheetStock|sheet inventory|quantity.*∞|infinite/i)
    errors << "missing layer filter requirement" unless content.match?(/layer.*(filter|select|checklist)|ProjectLayer/i)
    errors << "missing CLI contract (config.json or nesting_engine)" unless content.match?(/CLI|config\.json|nesting_engine/i)

    raise SpecDocError, errors.join("; ") if errors.any?

    true
  end
end

class SpecDocError < StandardError; end
