# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project CRUD", type: :request do
  describe "POST /projects [REQ-FIT-UI-001]" do
    it "creates a project with ordered finite and infinite sheet stocks" do
      post projects_path, params: {
        project: {
          title: "Bench project",
          pin: "778899",
          sheet_stocks_attributes: {
            "0" => { width_mm: 1000, height_mm: 2000, quantity: 5, sort_order: 0 },
            "1" => { width_mm: 500, height_mm: 300, quantity: "", sort_order: 1 }
          }
        }
      }

      project = Project.find_by!(title: "Bench project")
      expect(response).to redirect_to(project_path(project))

      stocks = project.sheet_stocks.order(:sort_order).to_a
      expect(stocks.size).to eq(2)
      expect(stocks[0].width_mm).to eq(1000)
      expect(stocks[0].quantity).to eq(5)
      expect(stocks[1].width_mm).to eq(500)
      expect(stocks[1].quantity).to be_nil
      expect(stocks.map(&:sort_order)).to eq([ 0, 1 ])
    end
  end
end
