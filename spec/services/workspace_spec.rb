# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workspace do
  before { Project.destroy_all }

  describe ".purge_all_ephemeral!" do
    it "removes all ephemeral projects and sheet stocks" do
      ephemeral = Project.create!(ephemeral: true, title: "Ephemeral", status: :draft)
      ephemeral.sheet_stocks.create!(width_mm: 1000, height_mm: 1000, quantity: 1, sort_order: 0)
      Project.create!(
        ephemeral: false,
        title: "Saved",
        pin: "123456",
        sheet_stocks_attributes: { "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 } }
      )

      count = described_class.purge_all_ephemeral!

      expect(count).to eq(1)
      expect(Project.ephemeral.count).to eq(0)
      expect(SheetStock.count).to eq(1)
    end
  end

  describe ".purge_all!" do
    it "removes every project and sheet stock" do
      Project.create!(ephemeral: true, title: "A", status: :draft)
      Project.create!(
        ephemeral: false,
        title: "B",
        pin: "123456",
        sheet_stocks_attributes: { "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 } }
      )

      counts = described_class.purge_all!

      expect(counts[:projects]).to eq(2)
      expect(Project.count).to eq(0)
      expect(SheetStock.count).to eq(0)
    end
  end

  describe ".resolve!" do
    it "rejects ephemeral project ids not bound to the session" do
      project = Project.create!(ephemeral: true, title: "Other", status: :draft)

      expect do
        described_class.resolve!({}, project.id)
      end.to raise_error(ActiveRecord::RecordNotFound, /not bound/)
    end

    it "allows non-ephemeral projects for legacy PIN flows" do
      saved = Project.create!(
        ephemeral: false,
        title: "Saved",
        pin: "123456",
        sheet_stocks_attributes: { "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 } }
      )

      expect(described_class.resolve!({}, saved.id)).to eq(saved)
    end
  end
end
