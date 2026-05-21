# frozen_string_literal: true

require "rails_helper"

RSpec.describe "I18n view copy", type: :request do
  self.use_transactional_tests = false

  def with_locale(locale)
    cookies[:fitloop_locale] = locale.to_s
    I18n.with_locale(locale) { yield }
  end

  describe "GET /projects/new [REQ-FIT-UI-005]" do
    it "renders English form labels" do
      with_locale(:en) { get new_project_path }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("activerecord.attributes.sheet_stock.width_mm", locale: :en))
      expect(response.body).to include(I18n.t("projects.form.sheet_stocks_legend", locale: :en))
      expect(response.body).to include(I18n.t("projects.form.consumption_priority", locale: :en))
      expect(response.body).to include(I18n.t("projects.form.consumption_order_legend", locale: :en))
      expect(response.body).not_to include('name="project[pin]"')
    end

    it "renders Spanish form labels" do
      with_locale(:es) { get new_project_path }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("activerecord.attributes.sheet_stock.width_mm", locale: :es))
      expect(response.body).to include(I18n.t("projects.form.quantity_hint", locale: :es))
      expect(response.body).to include(I18n.t("projects.form.dxf_upload_legend", locale: :es))
      expect(response.body).to include(I18n.t("projects.form.consumption_priority", locale: :es))
      expect(response.body).to include(I18n.t("projects.form.consumption_order_legend", locale: :es))
      expect(response.body).to include(I18n.t("projects.form.kerf_mm", locale: :es))
      expect(response.body).not_to include("Unlimited quantity")
      expect(response.body).not_to include("Kerf")
      expect(response.body).not_to include('name="project[pin]"')
    end
  end

  describe "GET /projects [REQ-FIT-UI-003] [REQ-FIT-UI-005]" do
    before { Project.destroy_all }

    it "redirects Spanish locale index to empezar" do
      with_locale(:es) { get projects_path }

      expect(response).to redirect_to(start_project_path)
    end
  end

  describe "GET /projects/:id/edit sheet inventory [REQ-FIT-UI-001] [REQ-FIT-UI-005]" do
    it "renders Spanish sheet consumption priority copy for the workspace project" do
      get start_project_path
      follow_redirect!
      project = Project.find(session[:workspace_project_id])

      with_locale(:es) { get edit_project_path(project) }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("projects.form.consumption_priority", locale: :es))
      expect(response.body).to include(I18n.t("projects.form.consumption_order_legend", locale: :es))
      expect(response.body).to include(I18n.t("projects.form.alert_single_unlimited", locale: :es))
      expect(response.body).not_to include('name="project[pin]"')
    end
  end
end
