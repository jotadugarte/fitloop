# frozen_string_literal: true

require "rails_helper"

RSpec.describe Project, type: :model do
  describe "user PIN on create [REQ-FIT-AUTH-001]" do
    it "requires a 6-digit PIN" do
      project = described_class.new(title: "Bench", pin: "12345")

      expect(project).not_to be_valid
      expect(project.errors[:pin]).to be_present
    end

    it "rejects non-numeric PIN" do
      project = described_class.new(title: "Bench", pin: "12ab56")

      expect(project).not_to be_valid
      expect(project.errors[:pin]).to be_present
    end

    it "stores a bcrypt digest when a valid PIN is assigned" do
      project = described_class.create!(title: "Bench", pin: "123456")

      expect(project.pin_digest).to be_present
      expect(project.pin_digest).to start_with("$2a$")
    end
  end
end
