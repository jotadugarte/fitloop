# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/architecture_doc_verifier"

# [REQ-FIT-ARCH-001] SYSTEM_ARCHITECTURE.md locks Fitloop stack and forbids nesting in Ruby.
class SystemArchitectureDocTest < Minitest::Test
  def test_system_architecture_doc_matches_fitloop_stack
    assert ArchitectureDocVerifier.verify!
  end
end
