# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Legal placeholder pages", type: :request do
  describe "GET /terminos [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] renders placeholder terms (D16)" do
      get terminos_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="legal-terms"')
      expect(response.body).to include(I18n.t("legal.terms.title"))
      expect(response.body).to include(TermsVersion.current)
    end
  end

  describe "GET /privacidad [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] renders placeholder privacy policy (D16)" do
      get privacidad_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="legal-privacy"')
      expect(response.body).to include(I18n.t("legal.privacy.title"))
      expect(response.body).to include(TermsVersion.current)
    end
  end

  describe "GET /crear-cuenta [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] links terms checkbox to legal pages" do
      get new_user_registration_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="terms-acceptance"')
      expect(response.body).to include(terminos_path)
      expect(response.body).to include(privacidad_path)
    end
  end
end
