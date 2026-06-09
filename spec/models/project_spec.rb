# frozen_string_literal: true

require "rails_helper"

RSpec.describe Project, type: :model do
  subject(:project) { described_class.new(title: "Atelier bench") }

  describe "defaults [REQ-FIT-DOM-001]" do
    it "sets kerf_mm to 0" do
      expect(project.kerf_mm).to eq(0)
    end

    it "sets margin_mm to 5" do
      expect(project.margin_mm).to eq(5)
    end

    it "sets curve_tolerance_mm to 0.1" do
      expect(project.curve_tolerance_mm).to eq(0.1)
    end

    it "sets sheet_gap_mm to 15" do
      expect(project.sheet_gap_mm).to eq(15)
    end

    it "sets nesting_time_limit_sec to 600" do
      expect(project.nesting_time_limit_sec).to eq(600)
    end

    it "defaults status to draft" do
      expect(project.status).to eq("draft")
    end
  end

  describe "associations [REQ-FIT-DOM-001]" do
    it "has many sheet_stocks, project_layers, and nesting_runs" do
      names = described_class.reflect_on_all_associations.map(&:name)

      expect(names).to include(:sheet_stocks, :project_layers, :nesting_runs)
    end
  end

  describe "#workshop_setup_mode? [REQ-FIT-UI-001]" do
    let(:project) { described_class.create!(title: "Bench", ephemeral: true, status: :draft) }

    it "is true for draft projects without nesting runs" do
      expect(project).to be_workshop_setup_mode
    end

    it "is false once a nesting run exists" do
      project.nesting_runs.create!(status: "processing", params_snapshot: {})

      expect(project).not_to be_workshop_setup_mode
    end

    it "is false when status is not draft" do
      project.status = "completed"
      expect(project).not_to be_workshop_setup_mode
    end
  end

  describe "ephemeral workspace [REQ-FIT-AUTH-001] [REQ-FIT-DOM-001]" do
    it "defaults ephemeral to true" do
      expect(described_class.new.ephemeral).to be(true)
    end

    it "does not expose pin_digest on the schema" do
      described_class.reset_column_information
      expect(described_class.column_names).not_to include("pin_digest")
    end

    it "creates an ephemeral project without PIN attributes" do
      project = described_class.create!(
        title: "Bench",
        ephemeral: true,
        status: :draft
      )

      expect(project).to be_persisted
      expect(project).to be_ephemeral
    end
  end

  describe "validations [REQ-FIT-DOM-001]" do
    it "requires sheet stocks for non-ephemeral projects" do
      project = described_class.new(title: "Non-ephemeral", ephemeral: false)
      expect(project).not_to be_valid
      expect(project.errors[:base]).to include(
        I18n.t("activerecord.errors.models.project.attributes.base.no_sheet_stocks")
      )
    end

    it "allows non-ephemeral project with a sheet stock" do
      project = described_class.new(title: "Non-ephemeral", ephemeral: false)
      project.sheet_stocks.build(width_mm: 1000, height_mm: 1000, quantity: 1)
      expect(project).to be_valid
    end
  end
end
