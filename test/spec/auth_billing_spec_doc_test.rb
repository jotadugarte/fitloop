# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/auth_billing_spec_doc_verifier"

# [REQ-FIT-AUTH-002] [REQ-FIT-BILL-001] [REQ-FIT-BILL-002] [REQ-FIT-BILL-003]
# SPEC.md traceability + detail sections; ADR-0005 (auth) + ADR-0006 (ONVO live billing).
class AuthBillingSpecDocTest < Minitest::Test
  def test_auth_and_billing_requirements_are_documented
    assert AuthBillingSpecDocVerifier.verify!
  end
end
