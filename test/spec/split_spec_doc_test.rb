# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/split_spec_doc_verifier"

# [REQ-FIT-SPLIT-001] SPEC.md and DATA_FLOW_MAP.md document the v1.1 auto-split workflow.
class SplitSpecDocTest < Minitest::Test
  def test_split_requirement_detail_is_documented
    assert SplitSpecDocVerifier.verify!
  end
end
