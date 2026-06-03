# frozen_string_literal: true

require "rails_helper"

RSpec.describe TermsVersion, "[REQ-FIT-AUTH-002]", type: :model do
  describe "CURRENT" do
    it "is set to 2026-06-01" do
      expect(TermsVersion::CURRENT).to eq("2026-06-01")
    end
  end
end
