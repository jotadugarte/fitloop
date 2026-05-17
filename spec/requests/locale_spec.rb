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

      expect(response.body).to include('aria-label="Language"')
      expect(response.body).to include("EN")
      expect(response.body).to include("ES")
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

    it "ignores unsupported locales" do
      patch locale_path, params: { locale: "fr" }, headers: { "HTTP_REFERER" => root_url }

      expect(response).to redirect_to(root_url)
      expect(cookies[:fitloop_locale]).to be_nil
    end
  end
end
