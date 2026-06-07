# frozen_string_literal: true

require "rails_helper"

RSpec.describe PersistWorkspaceSheetInventoryDraft, "[REQ-FIT-UI-005]" do
  let(:service) { described_class.new(session: session, params: params) }
  let(:session) { {} }
  let(:params) { ActionController::Parameters.new }

  describe "#normalize_sheet_quantities!" do
    it "coerces string-key quantities, blank values, and skips non-hash rows" do
      attrs = {
        "0" => { "quantity" => "4" },
        "1" => { quantity: "" },
        "2" => "not-a-hash"
      }

      service.send(:normalize_sheet_quantities!, attrs)

      expect(attrs["0"][:quantity]).to eq(4)
      expect(attrs["1"][:quantity]).to be_nil
    end
  end

  describe "#kept_sheet_stock_ids" do
    it "reads string ids and skips blank or non-hash rows" do
      ids = service.send(:kept_sheet_stock_ids, {
        "0" => { "id" => "12" },
        "1" => { id: "" },
        "2" => "skip"
      })

      expect(ids).to eq([ 12 ])
    end
  end

  it "does not stash composer draft when save fails" do
    project = Project.create!(ephemeral: true, title: "Persist draft fail", status: :draft)
    session = { Workspace::SESSION_KEY => project.id }
    params = ActionController::Parameters.new(
      project: {
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
        }
      },
      composer_draft: { width_mm: "1200", height_mm: "2400", quantity: "2" }
    )
    allow(Workspace).to receive(:any_bound_project).and_return(project)
    allow(project).to receive(:save).and_return(false)

    expect(described_class.call(session: session, params: params)).to be(false)
    expect(session[described_class::COMPOSER_SESSION_KEY]).to be_nil
  end

  it "stashes composer draft after a successful save" do
    project = Project.create!(ephemeral: true, title: "Persist draft ok", status: :draft)
    session = { Workspace::SESSION_KEY => project.id }
    params = ActionController::Parameters.new(
      project: {
        sheet_stocks_attributes: {
          "0" => {
            width_mm: 1200,
            height_mm: 2400,
            quantity: "2",
            sort_order: 0,
            _destroy: "0"
          }
        }
      },
      composer_draft: { width_mm: "1200", height_mm: "2400", quantity: "2" }
    )

    expect(described_class.call(session: session, params: params)).to be(true)
    expect(session[described_class::COMPOSER_SESSION_KEY]).to include("width_mm" => "1200")
  end

  it "returns false when omitting all persisted stock ids" do
    project = create_project_for_spec!(title: "Omit stock ids", bind_workspace: false)
    session = { Workspace::SESSION_KEY => project.id }
    params = ActionController::Parameters.new(
      project: {
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
        }
      }
    )

    expect(described_class.call(session: session, params: params)).to be(false)
  end

  it "skips stashing when composer draft values are blank" do
    project = Project.create!(ephemeral: true, title: "Blank composer", status: :draft)
    session = { Workspace::SESSION_KEY => project.id }
    params = ActionController::Parameters.new(
      project: {
        sheet_stocks_attributes: {
          "0" => {
            width_mm: 1200,
            height_mm: 2400,
            quantity: "2",
            sort_order: 0,
            _destroy: "0"
          }
        }
      },
      composer_draft: { width_mm: "", height_mm: "", quantity: "" }
    )

    expect(described_class.call(session: session, params: params)).to be(true)
    expect(session[described_class::COMPOSER_SESSION_KEY]).to be_nil
  end
end
