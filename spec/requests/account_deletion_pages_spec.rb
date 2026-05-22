# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account deletion pages", type: :request do
  let(:user) do
    User.create!(
      email: "delete-me@example.com",
      password: "securepassword12",
      password_confirmation: "securepassword12",
      name: "Delete User",
      terms_accepted_at: Time.current,
      terms_version: "v1-placeholder",
      time_zone: "America/Costa_Rica"
    )
  end

  before do
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "GET /eliminar-cuenta [REQ-FIT-AUTH-002]" do
    it "uses billing-style layout panels" do
      get account_deletion_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="account-deletion-new"')
      expect(response.body).to include("paywall-layout")
      expect(response.body).to include("panel--chrome")
      expect(response.body).to include(I18n.t("auth.account_deletion.aside.title"))
      expect(response.body).to include('class="btn btn-primary')
    end
  end

  describe "GET /eliminar-cuenta/confirmar [REQ-FIT-AUTH-002]" do
    it "shows confirm form after acknowledging deletion" do
      post account_deletion_path
      get confirm_account_deletion_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="account-deletion-confirm"')
      expect(response.body).to include('data-testid="account-deletion-form"')
      expect(response.body).to include("account-deletion-form__submit")
      expect(response.body).to include(I18n.t("auth.account_deletion.submit"))
    end
  end
end
