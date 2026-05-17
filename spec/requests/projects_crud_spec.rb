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
      expect(response).to redirect_to(project_layers_path(project))

      stocks = project.sheet_stocks.order(:sort_order).to_a
      expect(stocks.size).to eq(2)
      expect(stocks[0].width_mm).to eq(1000)
      expect(stocks[0].quantity).to eq(5)
      expect(stocks[1].width_mm).to eq(500)
      expect(stocks[1].quantity).to be_nil
      expect(stocks.map(&:sort_order)).to eq([ 0, 1 ])
    end

    it "attaches DXF files and redirects to the layers page" do
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")

      post projects_path, params: {
        project: {
          title: "DXF on create",
          pin: "112233",
          sheet_stocks_attributes: {
            "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
          }
        },
        files: [
          fixture_file_upload(sample_dxf, "piece.dxf", "application/dxf")
        ]
      }

      project = Project.find_by!(title: "DXF on create")
      expect(response).to redirect_to(project_layers_path(project))
      expect(project.input_dxf.count).to eq(1)
      expect(project.project_layers.pluck(:layer_name)).to include("PIECES")
    end

    it "re-renders the form with entered values when sheet inventory validation fails" do
      post projects_path, params: {
        project: {
          title: "Proyecto sin láminas",
          pin: "445566"
        },
        composer_draft: {
          width_mm: "1200",
          height_mm: "2400",
          quantity: "3"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Proyecto sin láminas")
      expect(response.body).to include('value="445566"')
      expect(response.body).to include('name="composer_draft[width_mm]"')
      expect(response.body).to include('value="1200"')
      expect(response.body).to include('value="2400"')
      expect(response.body).to include('value="3"')
      expect(Project.find_by(title: "Proyecto sin láminas")).to be_nil
    end

    it "re-renders sheet rows when another validation fails" do
      post projects_path, params: {
        project: {
          title: "Proyecto con PIN inválido",
          pin: "abc",
          sheet_stocks_attributes: {
            "0" => { width_mm: 900, height_mm: 1800, quantity: "", sort_order: 0 }
          }
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Proyecto con PIN inválido")
      expect(response.body).to include('value="abc"')
      expect(response.body).to include('name="project[sheet_stocks_attributes][0][width_mm]"')
      expect(response.body).to include('value="900.0"').or include('value="900"')
      expect(Project.find_by(title: "Proyecto con PIN inválido")).to be_nil
    end
  end
end
