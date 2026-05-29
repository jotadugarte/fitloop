# frozen_string_literal: true

require "rails_helper"

RSpec.describe "User sign in", "[REQ-FIT-AUTH-002]", type: :request do
  let(:user) { create_billing_user!(email: "signin@example.com") }

  describe "GET /iniciar-sesion [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] labels the password field for sign-in, not new password" do
      I18n.with_locale(:es) do
        get new_user_session_path

        expect(response.body).to include(I18n.t("auth.session.password"))
        expect(response.body).not_to include(">Nueva contraseña<")
      end
    end
  end

  describe "POST /iniciar-sesion [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] shows invalid credentials inside the sign-in form (not only top flash)" do
      I18n.with_locale(:es) do
        post user_session_path,
             params: { user: { email: user.email, password: "wrong-password-12" } }

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-testid="auth-errors"')
        expect(response.body).to include(I18n.t("devise.failure.invalid"))
        expect(response.body.scan('data-testid="auth-errors"').size).to eq(1)
        expect(response.body).not_to include('data-testid="flash-alert"')
      end
    end

    it "[REQ-FIT-AUTH-002] shows translated signed-in flash in Spanish" do
      I18n.with_locale(:es) do
        post user_session_path,
             params: { user: { email: user.email, password: "securepassword12" } }

        follow_redirect!
        expect(response.body).to include(I18n.t("devise.sessions.user.signed_in"))
        expect(response.body).to include('data-controller="flash-dismiss"')
        expect(response.body).to include("data-turbo-temporary")
        expect(response.body).not_to include("translation missing")
      end
    end
  end
end
