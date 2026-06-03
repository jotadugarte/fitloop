# frozen_string_literal: true

require "rails_helper"

RSpec.describe "App toolbar", "[REQ-FIT-UI-004] [REQ-FIT-AUTH-001]", type: :request do
  describe "GET / [REQ-FIT-UI-004]" do
    it "[REQ-FIT-UI-004] places locale switcher before account actions and does not render Mi taller link on home page" do
      get root_path

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).not_to include('data-testid="toolbar-workshop"')
      expect(body).not_to include(I18n.t("auth.nav.workshop"))
      expect(body.index("locale-switcher")).to be < body.index("account-nav")
    end

    it "[REQ-FIT-UI-004] renders Mi taller link on other pages" do
      user = create_billing_user!
      sign_in user
      get planes_path

      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include('data-testid="toolbar-workshop"')
      expect(body).to include(I18n.t("auth.nav.workshop"))
      expect(body).to include(workshop_path)
    end
  end

  describe "GET /taller with stale workshop bind [REQ-FIT-AUTH-001]" do
    it "[REQ-FIT-AUTH-001] redirects to empezar when the bound project was discarded" do
      project = begin_workspace_session!
      project.destroy!

      get workshop_path

      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.expired"))
    end
  end

  describe "GET /taller [REQ-FIT-AUTH-001]" do
    let(:user) { create_billing_user! }

    it "[REQ-FIT-AUTH-001] links Mi taller to the bound ephemeral project" do
      project = begin_workspace_session!
      sign_in user

      get workshop_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(href="#{workshop_path}"))
      expect(response.body).to include('data-testid="toolbar-workshop"')
    end
  end
end
