# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Account email collision merge", type: :request do
  def create_email_user!(email: "shared@example.com")
    User.new(
      email: email,
      password: "securepassword12",
      password_confirmation: "securepassword12",
      name: "Email User",
      terms_accepted_at: Time.current,
      terms_version: "v1-placeholder",
      time_zone: "America/Costa_Rica",
      confirmed_at: Time.current
    ).tap(&:skip_confirmation_notification!).tap(&:save!)
  end

  def mock_google_oauth(email:, uid: "google-uid-99")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid,
      info: OmniAuth::AuthHash::InfoHash.new(
        email: email,
        name: "OAuth User"
      )
    )
  end

  describe "OAuth callback collision [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] does not silently merge; redirects to merge offer" do
      existing = create_email_user!
      mock_google_oauth(email: existing.email)

      expect do
        get user_google_oauth2_omniauth_callback_path
      end.not_to change(User, :count)

      expect(response).to redirect_to(fusionar_cuenta_path)
      expect(existing.reload.provider).to be_nil
    end

    it "[REQ-FIT-AUTH-002] shows merge opt-in screen" do
      create_email_user!
      mock_google_oauth(email: "shared@example.com")
      get user_google_oauth2_omniauth_callback_path
      follow_redirect!

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("auth.merge.offer_title"))
      expect(response.body).to include(I18n.t("auth.merge.accept"))
      expect(response.body).to include(I18n.t("auth.merge.decline"))
    end
  end

  describe "declining merge [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] leaves existing account unchanged and shows error path" do
      existing = create_email_user!
      mock_google_oauth(email: existing.email)
      get user_google_oauth2_omniauth_callback_path
      follow_redirect!

      expect do
        delete cancel_fusionar_cuenta_path
      end.not_to change(User, :count)

      expect(existing.reload.provider).to be_nil
      expect(response).to redirect_to(new_user_session_path)
      follow_redirect!
      expect(flash[:alert]).to eq(I18n.t("auth.merge.declined"))
    end
  end
end
