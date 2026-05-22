# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Email confirmation pages", type: :request do
  describe "GET /confirmacion/new [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] uses auth layout styling without Devise default OAuth links" do
      get new_user_confirmation_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="auth-page"')
      expect(response.body).to include(I18n.t("auth.confirmation.resend_title"))
      expect(response.body).not_to include("Sign in with GoogleOauth2")
      expect(response.body).not_to include("Sign up")
      expect(response.body).to include(I18n.t("auth.nav.sign_in"))
    end

    it "[REQ-FIT-AUTH-002] pre-fills email when the user is signed in" do
      user = User.new(
        email: "pending@example.com",
        password: "securepassword12",
        password_confirmation: "securepassword12",
        name: "Pending User",
        terms_accepted_at: Time.current,
        terms_version: "v1-placeholder",
        time_zone: "America/Costa_Rica"
      ).tap(&:skip_confirmation_notification!).tap(&:save!)

      post user_session_path,
           params: { user: { email: user.email, password: "securepassword12" } }

      get new_user_confirmation_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('value="pending@example.com"')
    end
  end

  describe "GET /confirmacion-pendiente [REQ-FIT-AUTH-002]" do
    let(:unconfirmed_user) do
      User.new(
        email: "pending@example.com",
        password: "securepassword12",
        password_confirmation: "securepassword12",
        name: "Pending User",
        terms_accepted_at: Time.current,
        terms_version: "v1-placeholder",
        time_zone: "America/Costa_Rica"
      ).tap(&:skip_confirmation_notification!).tap(&:save!)
    end

    before do
      post user_session_path,
           params: { user: { email: unconfirmed_user.email, password: "securepassword12" } }
    end

    it "[REQ-FIT-AUTH-002] shows pending confirmation guidance" do
      get email_confirmation_pending_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("auth.confirmation.pending_title"))
      expect(response.body).to include(I18n.t("auth.confirmation.resend_link"))
      expect(response.body).not_to include("Sign in with GoogleOauth2")
    end
  end
end
