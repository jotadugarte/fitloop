# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../config/environment"
require_relative "../../lib/spec_doc_verifier"

# [REQ-FIT-SPEC-001] SPEC.md defines Fitloop domain, workflows, and REQ-FIT-* traceability.
class SpecDocTest < Minitest::Test
  def test_spec_doc_matches_fitloop_mvp_requirements
    assert SpecDocVerifier.verify!
  end
end
