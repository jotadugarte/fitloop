# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account deletion pages", "[REQ-FIT-AUTH-002]", type: :request do
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

  describe "GET /eliminar-cuenta/confirmar without acknowledgment" do
    it "redirects to the restart step" do
      get confirm_account_deletion_path

      expect(response).to redirect_to(account_deletion_path)
      expect(flash[:alert]).to eq(I18n.t("auth.account_deletion.restart"))
    end
  end

  describe "DELETE /eliminar-cuenta without acknowledgment" do
    it "redirects to the restart step" do
      delete account_deletion_path, params: {
        user: {
          current_password: "securepassword12",
          confirm_phrase: I18n.t("auth.account_deletion.confirm_phrase_expected")
        }
      }

      expect(response).to redirect_to(account_deletion_path)
      expect(flash[:alert]).to eq(I18n.t("auth.account_deletion.restart"))
    end
  end

  describe "DELETE /eliminar-cuenta with validation failures" do
    before do
      post account_deletion_path
    end

    it "renders confirm with unprocessable entity status when password is invalid" do
      delete account_deletion_path, params: {
        user: {
          current_password: "wrongpassword",
          confirm_phrase: I18n.t("auth.account_deletion.confirm_phrase_expected")
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to eq(I18n.t("auth.account_deletion.invalid_password"))
    end

    it "renders confirm with unprocessable entity status when confirmation phrase is invalid" do
      delete account_deletion_path, params: {
        user: {
          current_password: "securepassword12",
          confirm_phrase: "WRONG PHRASE"
        }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(flash.now[:alert]).to eq(I18n.t("auth.account_deletion.invalid_phrase"))
    end
  end

  describe "DELETE /eliminar-cuenta with valid credentials" do
    it "tracks event, signs out, deletes the user, and redirects to root" do
      post account_deletion_path

      expect(Analytics::TrackEvent).to receive(:call).with(
        "account_deleted",
        hash_including(
          user_id: user.id,
          properties: hash_including(
            historical_email: user.email,
            historical_name: user.name
          )
        )
      ).and_call_original

      delete account_deletion_path, params: {
        user: {
          current_password: "securepassword12",
          confirm_phrase: I18n.t("auth.account_deletion.confirm_phrase_expected")
        }
      }

      expect(response).to redirect_to(root_path)
      expect(flash[:notice]).to eq(I18n.t("auth.account_deletion.done"))
      expect(User.exists?(user.id)).to be(false)
    end
  end
end

