# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account edit page", type: :request do
  let(:user) { create_billing_user! }

  before do
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "GET /mi-cuenta [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] uses auth styling, Spanish copy, and no time zone field" do
      get edit_user_registration_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="auth-page"')
      expect(response.body).to include(I18n.t("auth.account.title"))
      expect(response.body).to include(I18n.t("auth.account.submit"))
      expect(response.body).not_to include("translation missing")
      expect(response.body).not_to include("Title")
      expect(response.body).not_to include("time_zone")
      expect(response.body).not_to include("Time zone")
    end
  end
end
