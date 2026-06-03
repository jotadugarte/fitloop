# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Architecture-studio UI", type: :request do
  self.use_transactional_tests = false

  describe "GET / [REQ-FIT-UI-004]" do
    it "renders tool hub with tools grid and app shell" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("home.hub.title"))
      expect(response.body).not_to include('class="app-sidebar"')
      expect(response.body).to include('class="page page--landing tool-hub"')
      expect(response.body).to include('class="tool-card tool-card--active"')
      expect(response.body).to include('class="tool-card tool-card--disabled"')
      expect(response.body).to include(workshop_path)
    end
  end

  describe "GET /projects [REQ-FIT-UI-003] [REQ-FIT-UI-004]" do
    it "redirects to empezar (ephemeral workspace; no saved list)" do
      get projects_path

      expect(response).to redirect_to(start_project_path)
    end
  end
end
