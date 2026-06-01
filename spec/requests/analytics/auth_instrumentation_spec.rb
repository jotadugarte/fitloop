# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth events telemetry", "[REQ-FIT-ANALYTICS-001]", type: :request do
  include ActiveJob::TestHelper

  describe "user_logged_in and user_logged_out events" do
    let(:user) { create_billing_user!(email: "auth-telemetry@example.com") }

    it "tracks user_logged_in on sign in" do
      expect {
        post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
      }.to have_enqueued_job(TrackEventJob).with("user_logged_in", anything)
    end

    it "tracks user_logged_out on sign out" do
      # Sign in first
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
      
      expect {
        delete destroy_user_session_path
      }.to have_enqueued_job(TrackEventJob).with("user_logged_out", anything)
    end
  end

  describe "account_registered and email_confirmed events" do
    it "tracks account_registered on successful registration" do
      expect {
        post user_registration_path, params: {
          user: {
            email: "newuser@example.com",
            name: "New User",
            password: "securepassword12",
            password_confirmation: "securepassword12",
            terms_accepted: "1",
            time_zone: "America/Costa_Rica"
          }
        }
      }.to change(UserEvent.where(event_type: "account_registered"), :count).by(1)
    end

    it "tracks email_confirmed when user confirmation is completed" do
      user = create_billing_user!(email: "unconfirmed@example.com")
      raw_token, enc_token = Devise.token_generator.generate(User, :confirmation_token)
      user.update!(confirmation_token: enc_token, confirmed_at: nil, confirmation_sent_at: Time.current)

      expect {
        get user_confirmation_path(confirmation_token: raw_token)
      }.to have_enqueued_job(TrackEventJob).with("email_confirmed", anything)
    end
  end

  describe "account_deleted event" do
    let!(:user) { create_billing_user!(email: "todelete@example.com").tap { |u| u.update!(name: "Delete Me") } }

    before do
      # Sign in
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
      # Acknowledge deletion
      post "/eliminar-cuenta"
    end

    it "tracks account_deleted with historical_email and historical_name synchronously on account deletion" do
      expect {
        delete "/eliminar-cuenta", params: {
          user: {
            current_password: "securepassword12",
            confirm_phrase: I18n.t("auth.account_deletion.confirm_phrase_expected")
          }
        }
      }.to change(UserEvent.where(event_type: "account_deleted"), :count).by(1)

      event = UserEvent.where(event_type: "account_deleted").last
      expect(event.priority).to eq("critical")
      expect(event.properties["historical_email"]).to eq("todelete@example.com")
      expect(event.properties["historical_name"]).to eq("Delete Me")
    end
  end
end
