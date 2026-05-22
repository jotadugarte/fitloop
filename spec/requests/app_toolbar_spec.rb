# frozen_string_literal: true

require "rails_helper"

RSpec.describe "App toolbar", type: :request do
  describe "GET / [REQ-FIT-UI-004]" do
    it "places locale switcher before account actions and links Mi taller to empezar without workshop" do
      get root_path

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include('data-testid="toolbar-workshop"')
      expect(body).to include(I18n.t("auth.nav.workshop"))
      expect(body).to include(start_project_path)
      expect(body.index("locale-switcher")).to be < body.index("account-nav")
    end
  end

  describe "GET /projects/:id with stale workshop bind [REQ-FIT-AUTH-001]" do
    it "redirects to empezar when the bound project was discarded" do
      project = begin_workspace_session!
      project_id = project.id
      project.destroy!

      get project_path(project_id)

      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.expired"))
    end
  end

  describe "GET /projects/:id [REQ-FIT-AUTH-001]" do
    let(:user) { create_billing_user! }

    it "links Mi taller to the bound ephemeral project" do
      project = begin_workspace_session!
      sign_in user

      get project_path(project)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{project_path(project)}"))
      expect(response.body).to include('data-testid="toolbar-workshop"')
    end
  end
end
