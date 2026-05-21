# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/composite_dxf_architecture_doc_verifier"

# [REQ-FIT-ARCH-001] [REQ-FIT-DXF-002] ADR-0003, README CLI schema, and ROADMAP document composite layers.
class CompositeDxfArchitectureDocTest < Minitest::Test
  def test_composite_dxf_architecture_docs_are_present
    assert CompositeDxfArchitectureDocVerifier.verify!
  end
end
