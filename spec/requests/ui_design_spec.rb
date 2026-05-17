# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Architecture-studio UI", type: :request do
  self.use_transactional_tests = false

  describe "GET / [REQ-FIT-UI-004]" do
    it "renders landing with architecture subtitle and app shell" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("home.index.subtitle"))
      expect(response.body).to include('class="app-sidebar"')
      expect(response.body).to include('class="landing-hero"')
    end
  end

  describe "GET /projects [REQ-FIT-UI-004]" do
    before { Project.delete_all }

    it "renders project grid when projects exist" do
      Project.create!(title: "UI grid test", pin: "112233")

      get projects_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('class="project-grid"')
    end

    it "renders empty state when there are no projects" do
      get projects_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="projects-empty"')
    end
  end
end
