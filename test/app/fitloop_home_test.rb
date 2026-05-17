# frozen_string_literal: true

require "minitest/autorun"
require_relative "../../lib/fitloop_home_verifier"

# [REQ-FIT-APP-001] Rails 8 Fitloop app with home route, branding, logo, and stack gems.
class FitloopHomeTest < Minitest::Test
  def test_fitloop_rails_app_and_home_page
    assert FitloopHomeVerifier.verify!
  end
end
