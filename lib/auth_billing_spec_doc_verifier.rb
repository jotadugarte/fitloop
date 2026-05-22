# frozen_string_literal: true

# [REQ-FIT-AUTH-002] [REQ-FIT-BILL-001] [REQ-FIT-BILL-002] [REQ-FIT-BILL-003]
# Validates auth + simulated billing requirements in core docs (ADR-0005 gate).
class AuthBillingSpecDocVerifier
  SPEC_PATH = File.expand_path("../docs/core/SPEC.md", __dir__)
  ADR_PATH = File.expand_path("../docs/core/ADRs/0005-user-accounts-and-simulated-billing.md", __dir__)

  REQUIRED_REQ_IDS = %w[
    REQ-FIT-AUTH-002
    REQ-FIT-BILL-001
    REQ-FIT-BILL-002
    REQ-FIT-BILL-003
  ].freeze

  DETAIL_HEADINGS = {
    "REQ-FIT-AUTH-002" => "### REQ-FIT-AUTH-002 (detail)",
    "REQ-FIT-BILL-001" => "### REQ-FIT-BILL-001 (detail)",
    "REQ-FIT-BILL-002" => "### REQ-FIT-BILL-002 (detail)",
    "REQ-FIT-BILL-003" => "### REQ-FIT-BILL-003 (detail)"
  }.freeze

  AUTH_MARKERS = [
    "Devise",
    "OmniAuth",
    "email_confirmed_at",
    "/iniciar-sesion",
    "/crear-cuenta",
    "merge",
    "terms_accepted_at",
    "suspended_at"
  ].freeze

  BILL_001_MARKERS = [
    "nested DXF",
    "billing.yml",
    "simulated",
    "USD",
    "CRC",
    "SINPE"
  ].freeze

  BILL_002_MARKERS = [
    "1",
    "2",
    "4",
    "50",
    "overage",
    "ends_at",
    "mis-pagos"
  ].freeze

  BILL_003_MARKERS = [
    "DownloadGrant",
    "signed",
    "retained_until",
    "24"
  ].freeze

  ADR_MARKERS = [
    "ADR-0004",
    "session[:workspaces]",
    "retained_nested_dxf",
    "billing.yml",
    "Devise"
  ].freeze

  def self.verify!
    new.verify!
  end

  def verify!
    errors = []
    spec_content = File.read(SPEC_PATH)

    REQUIRED_REQ_IDS.each do |req_id|
      errors << "missing requirement id in traceability: #{req_id}" unless spec_content.include?(req_id)
    end

    DETAIL_HEADINGS.each do |req_id, heading|
      errors << "missing SPEC detail heading: #{heading}" unless spec_content.include?(heading)

      section = extract_section(spec_content, heading)
      if section.nil? || section.empty?
        errors << "#{req_id} detail section is empty"
        next
      end

      markers_for(req_id).each do |marker|
        errors << "#{req_id} missing marker: #{marker}" unless section.match?(/#{Regexp.escape(marker)}/i)
      end
    end

    unless File.file?(ADR_PATH)
      errors << "missing ADR: docs/core/ADRs/0005-user-accounts-and-simulated-billing.md"
    else
      adr_content = File.read(ADR_PATH)
      ADR_MARKERS.each do |marker|
        errors << "ADR-0005 missing marker: #{marker}" unless adr_content.include?(marker)
      end
    end

    raise AuthBillingSpecDocError, errors.join("; ") if errors.any?

    true
  end

  private

  def markers_for(req_id)
    case req_id
    when "REQ-FIT-AUTH-002" then AUTH_MARKERS
    when "REQ-FIT-BILL-001" then BILL_001_MARKERS
    when "REQ-FIT-BILL-002" then BILL_002_MARKERS
    when "REQ-FIT-BILL-003" then BILL_003_MARKERS
    else []
    end
  end

  def extract_section(content, heading)
    start = content.index(heading)
    return nil unless start

    rest = content[(start + heading.length)..]
    next_heading = rest&.index(/\n### |\n## /)
    body = next_heading ? rest[0...next_heading] : rest
    body&.strip
  end
end

class AuthBillingSpecDocError < StandardError; end
