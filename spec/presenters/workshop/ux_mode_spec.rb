# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workshop::UxMode, "[REQ-FIT-UI-001]" do
  subject(:mode) { described_class.new(project) }

  let(:project) { Project.create!(title: "Bench", ephemeral: true, status: :draft) }

  describe "#setup?" do
    it "is true for draft projects without nesting runs" do
      expect(mode).to be_setup
    end

    it "is false after a nesting run exists" do
      project.nesting_runs.create!(status: "processing", params_snapshot: {})

      expect(mode).not_to be_setup
    end

    it "is false when status is not draft" do
      project.update!(status: :ready)

      expect(mode).not_to be_setup
    end
  end

  describe "visibility helpers" do
    it "hides preview and progress in setup mode" do
      expect(mode.show_preview_zone?).to be(false)
      expect(mode.show_nesting_progress?).to be(false)
      expect(mode.show_inline_nesting_settings?).to be(true)
    end

    it "shows workshop sections after the first nesting run" do
      project.nesting_runs.create!(status: "failed", params_snapshot: {})

      expect(mode.show_preview_zone?).to be(true)
      expect(mode.show_nesting_progress?).to be(true)
      expect(mode.show_inline_nesting_settings?).to be(false)
    end
  end
end
