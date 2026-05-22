# frozen_string_literal: true

require "rails_helper"

RSpec.describe "User sign in", type: :request do
  let(:user) { create_billing_user!(email: "signin@example.com") }

  describe "POST /iniciar-sesion [REQ-FIT-AUTH-002]" do
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
