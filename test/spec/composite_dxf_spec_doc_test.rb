# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/composite_dxf_spec_doc_verifier"

# [REQ-FIT-DXF-002] SPEC.md and DATA_FLOW_MAP.md document composite DXF layers.
class CompositeDxfSpecDocTest < Minitest::Test
  def test_composite_dxf_requirement_detail_is_documented
    assert CompositeDxfSpecDocVerifier.verify!
  end
end
