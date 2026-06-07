# frozen_string_literal: true

require "rails_helper"

RSpec.describe "User registration", "[REQ-FIT-AUTH-002]", type: :request do
  def registration_params(overrides = {})
    {
      user: {
        email: "newuser@example.com",
        password: "securepassword12",
        password_confirmation: "securepassword12",
        name: "Pat Smith",
        terms_accepted: "1",
        time_zone: "America/Costa_Rica"
      }.merge(overrides)
    }
  end

  describe "GET /crear-cuenta [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] shows password length requirements and live validation UI" do
      get new_user_registration_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(
        I18n.t("auth.password.length_hint", min: Devise.password_length.begin)
      )
      expect(response.body).to include("importmap")
      expect(response.body).to include('data-controller="password-validation"')
      expect(response.body).to include(
        I18n.t("auth.password.validation.too_short", min: Devise.password_length.begin)
      )
      expect(response.body).to include('data-password-validation-target="submit"')
    end
  end

  describe "POST /crear-cuenta [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] requires name" do
      expect do
        post user_registration_path, params: registration_params(name: "")
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "[REQ-FIT-AUTH-002] requires terms acceptance checkbox" do
      expect do
        post user_registration_path, params: registration_params(terms_accepted: "0")
      end.not_to change(User, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "[REQ-FIT-AUTH-002] creates user and sends confirmation email" do
      expect do
        post user_registration_path, params: registration_params
      end.to change(User, :count).by(1)
        .and change { ActionMailer::Base.deliveries.size }.by(1)

      created = User.find_by!(email: "newuser@example.com")
      expect(created.name).to eq("Pat Smith")
      expect(created.terms_accepted_at).to be_present
      expect(created.email_confirmed_at).to be_nil
    end

  end

  describe "checkout access before email confirmation [REQ-FIT-AUTH-002]" do
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

    before { sign_in unconfirmed_user }

    it "[REQ-FIT-AUTH-002] blocks GET /planes" do
      get "/planes"

      expect(response).to redirect_to("/confirmacion-pendiente")
    end

    it "[REQ-FIT-AUTH-002] blocks GET /checkout" do
      get "/checkout"

      expect(response).to redirect_to("/confirmacion-pendiente")
    end
  end
end
