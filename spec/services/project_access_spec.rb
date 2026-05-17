# frozen_string_literal: true

require "rails_helper"

RSpec.describe ProjectAccess do
  let(:project) { create_project_for_spec!(title: "Atelier", pin: "654321") }

  describe ".granted? [REQ-FIT-AUTH-001]" do
    it "returns true for the correct user PIN" do
      expect(described_class.granted?(project: project, pin: "654321")).to be(true)
    end

    it "returns false for an incorrect user PIN" do
      expect(described_class.granted?(project: project, pin: "000000")).to be(false)
    end

    it "returns true for the admin master PIN from credentials" do
      allow(Rails.application.credentials).to receive(:dig)
        .with(:fitloop, :admin_pin)
        .and_return("1098765432")

      expect(described_class.granted?(project: project, pin: "1098765432")).to be(true)
    end

    it "returns false when admin PIN is not configured" do
      allow(Rails.application.credentials).to receive(:dig)
        .with(:fitloop, :admin_pin)
        .and_return(nil)

      expect(described_class.granted?(project: project, pin: "1098765432")).to be(false)
    end
  end
end
