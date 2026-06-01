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

  CONTRACT_PATH = File.expand_path("../docs/core/ANALYTICS_AND_REPORTING_CONTRACT.md", __dir__)
  EVENT_CATALOG_PATH = File.expand_path("../config/analytics_event_catalog.yml", __dir__)
  ANALYTICS_CONFIG_PATH = File.expand_path("../config/analytics.yml", __dir__)

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

    verify_analytics_contract!(errors)

    raise SpecDocError, errors.join("; ") if errors.any?

    true
  end

  private

  def verify_analytics_contract!(errors)
    unless File.file?(CONTRACT_PATH)
      errors << "missing contract: docs/core/ANALYTICS_AND_REPORTING_CONTRACT.md"
      return
    end

    contract_content = File.read(CONTRACT_PATH)
    verify_event_catalog!(errors)
    verify_funnel_stages!(errors, contract_content)
    verify_xlsx_headers!(errors, contract_content)
    verify_threshold_keys!(errors, contract_content)
  end

  def verify_event_catalog!(errors)
    return errors << "missing config/analytics_event_catalog.yml" unless File.file?(EVENT_CATALOG_PATH)

    require "yaml"
    yaml_data = YAML.load_file(EVENT_CATALOG_PATH)
    return errors << "invalid config/analytics_event_catalog.yml format" unless yaml_data.is_a?(Hash)

    catalog_events = Analytics::EventCatalog.all_event_types
    yaml_data.each_key do |event|
      errors << "event type #{event} from catalog YAML not registered in Analytics::EventCatalog" unless catalog_events.include?(event)
    end
  rescue NameError
    errors << "Analytics::EventCatalog is not defined"
  end

  def verify_funnel_stages!(errors, contract_content)
    Analytics::FunnelStages::ORDERED.each do |stage|
      errors << "funnel stage #{stage} not found in contract" unless contract_content.include?(stage)
    end
  rescue NameError
    errors << "Analytics::FunnelStages::ORDERED is not defined"
  end

  def verify_xlsx_headers!(errors, contract_content)
    Admin::ExportPaymentsXlsx::DETAIL_HEADERS.each do |header|
      errors << "XLSX detail header '#{header}' not listed in contract" unless contract_content.include?(header)
    end
    Admin::ExportPaymentsXlsx::SUMMARY_HEADERS.each do |header|
      errors << "XLSX summary header '#{header}' not listed in contract" unless contract_content.include?(header)
    end
  rescue NameError
    errors << "Admin::ExportPaymentsXlsx is not defined"
  end

  def verify_threshold_keys!(errors, contract_content)
    return errors << "missing config/analytics.yml" unless File.file?(ANALYTICS_CONFIG_PATH)

    require "yaml"
    thresholds = YAML.load_file(ANALYTICS_CONFIG_PATH)
    return errors << "invalid config/analytics.yml format" unless thresholds.is_a?(Hash)

    thresholds.each_key do |key|
      errors << "threshold key '#{key}' not listed in contract" unless contract_content.include?(key)
    end
  end
end

class SpecDocError < StandardError; end
