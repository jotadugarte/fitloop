# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account edit page", type: :request do
  let(:user) { create_billing_user!(email: "keeper@example.com") }

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
      expect(response.body).to include(I18n.t("auth.account.change_password_toggle"))
      expect(response.body).to include(I18n.t("auth.account.email_readonly_hint"))
      expect(response.body).not_to include("translation missing")
      expect(response.body).not_to include("Title")
      expect(response.body).not_to include("time_zone")
      expect(response.body).not_to include('name="user[email]"')
      expect(response.body).to include("keeper@example.com")
      expect(response.body).to include('data-controller="password-validation"')
      expect(response.body).to include('data-password-validation-optional-value="true"')
      expect(response.body).to include(
        I18n.t("auth.password.validation.too_short", min: Devise.password_length.begin)
      )
    end

    it "[REQ-FIT-AUTH-002] lists password fields in current → new → confirm order" do
      get edit_user_registration_path

      current = response.body.index('name="user[current_password]"')
      password = response.body.index('name="user[password]"')
      confirmation = response.body.index('name="user[password_confirmation]"')

      expect(current).to be < password
      expect(password).to be < confirmation
    end
  end

  describe "PUT /mi-cuenta [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] updates name without password fields" do
      patch user_registration_path,
            params: { user: { name: "Updated Name", email: "hacker@evil.com" } }

      user.reload
      expect(user.name).to eq("Updated Name")
      expect(user.email).to eq("keeper@example.com")
    end

    it "[REQ-FIT-AUTH-002] shows translated flash after update" do
      I18n.with_locale(:es) do
        patch user_registration_path, params: { user: { name: "Flash Test" } }

        expect(response).to redirect_to(root_path)
        follow_redirect!

        expect(response.body).to include(I18n.t("devise.registrations.user.updated"))
        expect(response.body).not_to include("translation missing")
      end
    end
  end
end
