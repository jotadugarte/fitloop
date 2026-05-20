# frozen_string_literal: true

require "rails_helper"

RSpec.describe Workspace do
  before { Project.destroy_all }

  describe ".purge_all_ephemeral! [REQ-FIT-DOM-001]" do
    it "[REQ-FIT-DOM-001] removes all ephemeral projects and sheet stocks" do
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

  describe ".purge_all! [REQ-FIT-DOM-001]" do
    it "[REQ-FIT-DOM-001] removes every project and sheet stock" do
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

  describe ".resolve! [REQ-FIT-AUTH-001]" do
    it "[REQ-FIT-AUTH-001] returns the ephemeral project when the session is bound" do
      project = Project.create!(ephemeral: true, title: "Mine", status: :draft)
      session = { described_class::SESSION_KEY => project.id }

      expect(described_class.resolve!(session, project.id)).to eq(project)
    end

    it "[REQ-FIT-AUTH-001] raises when the ephemeral project id is not bound to the session" do
      project = Project.create!(ephemeral: true, title: "Other", status: :draft)

      expect do
        described_class.resolve!({}, project.id)
      end.to raise_error(ActiveRecord::RecordNotFound, /not bound/)
    end

    it "[REQ-FIT-AUTH-001] raises when the session is bound to a different project" do
      mine = Project.create!(ephemeral: true, title: "Mine", status: :draft)
      other = Project.create!(ephemeral: true, title: "Other", status: :draft)
      session = { described_class::SESSION_KEY => mine.id }

      expect do
        described_class.resolve!(session, other.id)
      end.to raise_error(ActiveRecord::RecordNotFound, /not bound/)
    end

    it "[REQ-FIT-AUTH-001] raises when the project id does not exist" do
      session = { described_class::SESSION_KEY => 999_999 }

      expect do
        described_class.resolve!(session, 999_999)
      end.to raise_error(ActiveRecord::RecordNotFound, /discarded/)
    end

    it "[REQ-FIT-AUTH-001] raises when the bound project was discarded" do
      project = Project.create!(ephemeral: true, title: "Gone", status: :draft)
      session = { described_class::SESSION_KEY => project.id }
      project.destroy!

      expect do
        described_class.resolve!(session, project.id)
      end.to raise_error(ActiveRecord::RecordNotFound, /discarded/)
    end

    it "[REQ-FIT-AUTH-001] does not resolve non-ephemeral projects by id" do
      saved = Project.create!(
        ephemeral: false,
        title: "Saved",
        pin: "123456",
        sheet_stocks_attributes: { "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 } }
      )
      session = { described_class::SESSION_KEY => saved.id }

      expect do
        described_class.resolve!(session, saved.id)
      end.to raise_error(ActiveRecord::RecordNotFound, /discarded/)
    end
  end
end
