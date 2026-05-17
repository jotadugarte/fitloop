# frozen_string_literal: true

require "rails_helper"

RSpec.describe NestingRun, type: :model do
  describe "associations [REQ-FIT-DOM-001]" do
    it "belongs to project" do
      expect(described_class.reflect_on_association(:project).macro).to eq(:belongs_to)
    end
  end

  describe "run metadata [REQ-FIT-DOM-001]" do
    it "stores status and optional report_json" do
      run = described_class.new(status: "processing", report_json: { "orphans" => [] })

      expect(run.status).to eq("processing")
      expect(run.report_json).to eq({ "orphans" => [] })
    end
  end
end
