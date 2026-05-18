# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project sheet inventory consumption order", type: :request do
  def quantities_by_consumption_rank(project)
    project.reload.sheet_stocks.order(:sort_order).map(&:quantity)
  end

  def ephemeral_workspace_project!(sheet_stocks_attributes:)
    project = start_setup_session!
    project.sheet_stocks.destroy_all
    sheet_stocks_attributes.each_value do |attrs|
      project.sheet_stocks.create!(attrs)
    end
    project.update!(status: :ready)
    project.reload
  end

  describe "PATCH /projects/:id/workspace (sheets) [REQ-FIT-UI-001]" do
    it "normalizes consumption order when saving sheet inventory from the workspace" do
      project = ephemeral_workspace_project!(
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

    it "drops sheet stocks omitted from the form submission" do
      project = ephemeral_workspace_project!(
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 },
          "1" => { width_mm: 1000, height_mm: 1000, quantity: 10, sort_order: 1 }
        }
      )
      keep = project.sheet_stocks.find_by!(height_mm: 1000, quantity: 10)

      patch workspace_project_path(project),
            params: {
              section: "sheets",
              project: {
                sheet_stocks_attributes: {
                  "0" => {
                    id: keep.id,
                    width_mm: keep.width_mm,
                    height_mm: keep.height_mm,
                    quantity: keep.quantity,
                    sort_order: 0,
                    _destroy: "0"
                  }
                }
              }
            },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(project.reload.sheet_stocks).to contain_exactly(keep)
    end

    it "deletes a sheet stock when _destroy is set" do
      project = ephemeral_workspace_project!(
        sheet_stocks_attributes: {
          "0" => { width_mm: 600, height_mm: 600, quantity: 2, sort_order: 0 },
          "1" => { width_mm: 1000, height_mm: 1000, quantity: 10, sort_order: 1 }
        }
      )
      first_stock, second_stock = project.sheet_stocks.order(:sort_order).to_a

      patch workspace_project_path(project),
            params: {
              section: "sheets",
              project: {
                sheet_stocks_attributes: {
                  "0" => {
                    id: first_stock.id,
                    width_mm: first_stock.width_mm,
                    height_mm: first_stock.height_mm,
                    quantity: first_stock.quantity,
                    sort_order: 0,
                    _destroy: "1"
                  },
                  "1" => {
                    id: second_stock.id,
                    width_mm: second_stock.width_mm,
                    height_mm: second_stock.height_mm,
                    quantity: second_stock.quantity,
                    sort_order: 1,
                    _destroy: "0"
                  }
                }
              }
            },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
      expect(project.reload.sheet_stocks.count).to eq(1)
      expect(project.sheet_stocks.first.width_mm).to eq(1000)
    end
  end
end
