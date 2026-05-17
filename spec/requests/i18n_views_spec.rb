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
      expect(response.body).to include(I18n.t("activerecord.attributes.project.title", locale: :en))
      expect(response.body).to include(I18n.t("activerecord.attributes.sheet_stock.width_mm", locale: :en))
      expect(response.body).to include(I18n.t("projects.form.sheet_stocks_legend", locale: :en))
    end

    it "renders Spanish form labels" do
      with_locale(:es) { get new_project_path }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("activerecord.attributes.project.title", locale: :es))
      expect(response.body).to include(I18n.t("activerecord.attributes.sheet_stock.width_mm", locale: :es))
      expect(response.body).to include(I18n.t("projects.form.quantity_hint", locale: :es))
      expect(response.body).to include(I18n.t("activerecord.attributes.project.pin", locale: :es))
      expect(response.body).not_to include(">Title<")
      expect(response.body).not_to include("Unlimited quantity")
    end
  end

  describe "GET /projects [REQ-FIT-UI-005]" do
    before { Project.destroy_all }

    it "renders Spanish index copy" do
      with_locale(:es) { get projects_path }

      expect(response.body).to include(I18n.t("projects.index.title", locale: :es))
      expect(response.body).to include(I18n.t("projects.index.new", locale: :es))
    end
  end

  describe "GET /projects/:id PIN gate [REQ-FIT-UI-005]" do
    let(:project) do
      Project.create!(
        title: "Puerta",
        pin: "123456",
        sheet_stocks_attributes: {
          "0" => { width_mm: 1000, height_mm: 500, quantity: 1, sort_order: 0 }
        }
      )
    end

    it "renders Spanish PIN gate copy" do
      with_locale(:es) { get project_path(project) }

      expect(response.body).to include(I18n.t("projects.access.prompt", locale: :es))
      expect(response.body).to include(I18n.t("projects.access.pin_label", locale: :es))
    end
  end
end
