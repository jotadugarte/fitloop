# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project sheet inventory consumption order", type: :request do
  def quantities_by_consumption_rank(project)
    project.reload.sheet_stocks.order(:sort_order).map(&:quantity)
  end

  describe "PATCH /projects/:id [REQ-FIT-UI-001]" do
    it "persists finite stocks before unlimited when nested attributes list unlimited first" do
      project = create_project_for_spec!(
        title: "Sheet inventory order",
        pin: "654321",
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: nil, sort_order: 0 },
          "1" => { width_mm: 800, height_mm: 1600, quantity: 5, sort_order: 1 }
        }
      )
      unlimited = project.sheet_stocks.find { |stock| stock.quantity.nil? }
      finite = project.sheet_stocks.find { |stock| stock.quantity.present? }
      unlock_project_for_spec!(project, pin: "654321")

      patch project_path(project), params: {
        project: {
          title: project.title,
          kerf_mm: project.kerf_mm,
          margin_mm: project.margin_mm,
          sheet_stocks_attributes: {
            "0" => {
              id: unlimited.id,
              width_mm: unlimited.width_mm,
              height_mm: unlimited.height_mm,
              quantity: "",
              sort_order: 0
            },
            "1" => {
              id: finite.id,
              width_mm: finite.width_mm,
              height_mm: finite.height_mm,
              quantity: finite.quantity,
              sort_order: 1
            }
          }
        }
      }

      expect(response).to redirect_to(project_path(project))
      expect(quantities_by_consumption_rank(project)).to eq([5, nil])
    end
  end

  describe "PATCH /projects/:id/workspace (sheets) [REQ-FIT-UI-001]" do
    it "normalizes consumption order when saving sheet inventory from the workspace" do
      project = Project.create!(
        ephemeral: true,
        status: :ready,
        title: I18n.t("workspace.default_title"),
        kerf_mm: 0,
        margin_mm: 5,
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: nil, sort_order: 0 },
          "1" => { width_mm: 800, height_mm: 1600, quantity: 3, sort_order: 1 }
        }
      )
      unlimited = project.sheet_stocks.find { |stock| stock.quantity.nil? }
      finite = project.sheet_stocks.find { |stock| stock.quantity.present? }

      patch workspace_project_path(project),
            params: {
              section: "sheets",
              project: {
                sheet_stocks_attributes: {
                  "0" => {
                    id: unlimited.id,
                    width_mm: unlimited.width_mm,
                    height_mm: unlimited.height_mm,
                    quantity: "",
                    sort_order: 0
                  },
                  "1" => {
                    id: finite.id,
                    width_mm: finite.width_mm,
                    height_mm: finite.height_mm,
                    quantity: finite.quantity,
                    sort_order: 1
                  }
                }
              }
            },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(quantities_by_consumption_rank(project)).to eq([3, nil])
    end
  end
end
