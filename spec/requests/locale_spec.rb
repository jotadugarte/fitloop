# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Locale switcher", type: :request do
  self.use_transactional_tests = false

  describe "GET / [REQ-FIT-UI-005]" do
    it "defaults to English copy" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("DXF sheet nesting")
    end

    it "renders Spanish copy when the locale cookie is set" do
      cookies[:fitloop_locale] = "es"
      get root_path

      expect(response.body).to include("Anidado de láminas DXF")
    end

    it "renders the EN/ES toggle in the layout" do
      get root_path

      expect(response.body).to include("aria-label=\"#{I18n.t('locale.switcher_row_primary')}\"")
      expect(response.body).to include("EN")
      expect(response.body).to include("ES")
    end

    it "localizes the EN/ES group aria-label in Spanish" do
      cookies[:fitloop_locale] = "es"
      get root_path

      label = I18n.t("locale.switcher_row_primary", locale: :es)
      expect(response.body).to include("aria-label=\"#{label}\"")
    end

    it "localizes the EN/ES group aria-label in es_panic" do
      cookies[:fitloop_locale] = "es_panic"
      get root_path

      label = I18n.t("locale.switcher_row_primary", locale: :es_panic)
      expect(response.body).to include("aria-label=\"#{label}\"")
    end

    it "renders panic copy when the locale cookie is set" do
      cookies[:fitloop_locale] = "es_panic"
      get root_path

      expect(response.body).to include("Tetris de supervivencia DXF")
    end

    it "renders the panic locale row with PÁNICO label, not ES_PANIC" do
      get root_path

      expect(response.body).to include("locale-switcher__row--panic")
      expect(response.body).to include("📐 PÁNICO")
      expect(response.body).not_to include("ES_PANIC")
    end
  end

  describe "PATCH /locale [REQ-FIT-UI-005]" do
    it "persists Spanish in cookie and session then redirects back" do
      patch locale_path, params: { locale: "es" }, headers: { "HTTP_REFERER" => root_url }

      expect(response).to redirect_to(root_url)
      expect(cookies[:fitloop_locale]).to eq("es")
      follow_redirect!
      expect(response.body).to include("Anidado de láminas DXF")
    end

    it "persists es_panic in cookie and session then redirects back" do
      patch locale_path, params: { locale: "es_panic" }, headers: { "HTTP_REFERER" => root_url }

      expect(response).to redirect_to(root_url)
      expect(cookies[:fitloop_locale]).to eq("es_panic")
      follow_redirect!
      expect(response.body).to include("Tetris de supervivencia DXF")
    end

    it "ignores unsupported locales" do
      patch locale_path, params: { locale: "fr" }, headers: { "HTTP_REFERER" => root_url }

      expect(response).to redirect_to(root_url)
      expect(cookies[:fitloop_locale]).to be_nil
    end
  end
end
