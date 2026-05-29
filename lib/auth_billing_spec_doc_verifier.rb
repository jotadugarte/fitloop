# frozen_string_literal: true

# [REQ-FIT-AUTH-002] [REQ-FIT-BILL-001] [REQ-FIT-BILL-002] [REQ-FIT-BILL-003]
# Validates auth + billing requirements in core docs (ADR-0005 + ADR-0006 ONVO gate).
class AuthBillingSpecDocVerifier
  SPEC_PATH = File.expand_path("../docs/core/SPEC.md", __dir__)
  ADR_PATH = File.expand_path("../docs/core/ADRs/0005-user-accounts-and-simulated-billing.md", __dir__)
  ADR_ONVO_PATH = File.expand_path("../docs/core/ADRs/0006-onvo-live-billing.md", __dir__)
  ARCHITECTURE_PATH = File.expand_path("../docs/core/SYSTEM_ARCHITECTURE.md", __dir__)
  ENV_EXAMPLE_PATH = File.expand_path("../.env.example", __dir__)
  DEPLOY_PATH = File.expand_path("../docs/DEPLOY.md", __dir__)

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
    "USD",
    "CRC",
    "SINPE"
  ].freeze

  BILL_001_ONVO_MARKERS = [
    "ONVO",
    "payment intent",
    "webhook",
    "BILLING_GATEWAY",
    "CheckoutBreakdown",
    "FulfillPayment",
    "/webhooks/onvo"
  ].freeze

  ADR_ONVO_MARKERS = [
    "ONVO",
    "payment-intent",
    "webhook",
    "ONVO_SECRET_KEY",
    "ONVO_WEBHOOK_SECRET",
    "BILLING_GATEWAY"
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

  ARCHITECTURE_ONVO_MARKERS = [
    "ADR-0006",
    "BILLING_GATEWAY",
    "Billing::Onvo",
    "/webhooks/onvo"
  ].freeze

  ARCHITECTURE_KILL_LIST_FORBIDDEN = "no Stripe, ONVO, or card capture in production paths until a follow-on ADR".freeze

  ENV_EXAMPLE_ONVO_MARKERS = %w[
    BILLING_GATEWAY
    ONVO_MODE
    ONVO_SECRET_KEY
    ONVO_PUBLISHABLE_KEY
    ONVO_WEBHOOK_SECRET
  ].freeze

  DEPLOY_ONVO_WEBHOOK_MARKERS = [
    "ngrok",
    "/webhooks/onvo",
    "4040"
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

      if req_id == "REQ-FIT-BILL-001"
        BILL_001_ONVO_MARKERS.each do |marker|
          errors << "#{req_id} missing ONVO marker: #{marker}" unless section.match?(/#{Regexp.escape(marker)}/i)
        end
      end
    end

    unless File.file?(ADR_ONVO_PATH)
      errors << "missing ADR: docs/core/ADRs/0006-onvo-live-billing.md"
    else
      adr_onvo_content = File.read(ADR_ONVO_PATH)
      ADR_ONVO_MARKERS.each do |marker|
        errors << "ADR-0006 missing marker: #{marker}" unless adr_onvo_content.include?(marker)
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

    verify_architecture_onvo!(errors)
    verify_env_example_onvo!(errors)
    verify_deploy_onvo_webhooks!(errors)

    raise AuthBillingSpecDocError, errors.join("; ") if errors.any?

    true
  end

  private

  def verify_architecture_onvo!(errors)
    unless File.file?(ARCHITECTURE_PATH)
      errors << "missing SYSTEM_ARCHITECTURE.md"
      return
    end

    arch = File.read(ARCHITECTURE_PATH)
    if arch.include?(ARCHITECTURE_KILL_LIST_FORBIDDEN)
      errors << "SYSTEM_ARCHITECTURE kill list still forbids ONVO (update per ADR-0006)"
    end

    ARCHITECTURE_ONVO_MARKERS.each do |marker|
      errors << "SYSTEM_ARCHITECTURE missing ONVO marker: #{marker}" unless arch.include?(marker)
    end
  end

  def verify_env_example_onvo!(errors)
    unless File.file?(ENV_EXAMPLE_PATH)
      errors << "missing .env.example"
      return
    end

    env_example = File.read(ENV_EXAMPLE_PATH)
    ENV_EXAMPLE_ONVO_MARKERS.each do |marker|
      errors << ".env.example missing: #{marker}" unless env_example.include?(marker)
    end
  end

  def verify_deploy_onvo_webhooks!(errors)
    unless File.file?(DEPLOY_PATH)
      errors << "missing docs/DEPLOY.md"
      return
    end

    deploy = File.read(DEPLOY_PATH)
    DEPLOY_ONVO_WEBHOOK_MARKERS.each do |marker|
      errors << "DEPLOY.md missing ONVO webhook marker: #{marker}" unless deploy.include?(marker)
    end
  end

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
