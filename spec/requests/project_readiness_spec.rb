# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Project pre-flight", type: :request do
  let(:project) { Project.create!(title: "Pre-flight UI", pin: "778899") }
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

  describe "GET /projects/:project_id/layers [REQ-FIT-VAL-001]" do
    it "shows i18n pre-flight errors when no layers are selected" do
      grant_project_access!(project, pin: "778899")

      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      project.project_layers.create!(layer_name: "PIECES", included: false)

      get project_layers_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="readiness-errors"')
      expect(response.body).to include(I18n.t("project_readiness.no_layers_selected"))
    end
  end
end
