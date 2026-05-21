# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Password recovery", type: :request do
  def create_confirmed_user!(email: "recover@example.com")
    User.new(
      email: email,
      password: "securepassword12",
      password_confirmation: "securepassword12",
      name: "Recovery User",
      terms_accepted_at: Time.current,
      terms_version: "v1-placeholder",
      time_zone: "America/Costa_Rica"
    ).tap(&:skip_confirmation_notification!).tap(&:save!).tap do |user|
      user.update!(confirmed_at: Time.current)
    end
  end

  def raw_reset_token_for(user)
    raw, enc = Devise.token_generator.generate(User, :reset_password_token)
    user.update!(reset_password_token: enc, reset_password_sent_at: Time.current)
    raw
  end

  describe "POST /contrasena [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] sends reset instructions email" do
      user = create_confirmed_user!

      expect do
        post user_password_path, params: { user: { email: user.email } }
      end.to change { ActionMailer::Base.deliveries.size }.by(1)

      expect(response).to redirect_to("/iniciar-sesion")
      follow_redirect!
      expect(flash[:notice]).to eq(I18n.t("auth.password.reset_sent"))
    end
  end

  describe "PATCH /contrasena [REQ-FIT-AUTH-002]" do
    let(:user) { create_confirmed_user! }
    let(:reset_token) { raw_reset_token_for(user) }

    it "[REQ-FIT-AUTH-002] rejects new passwords shorter than 12 characters" do
      patch user_password_path, params: {
        user: {
          reset_password_token: reset_token,
          password: "short10chr",
          password_confirmation: "short10chr"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.valid_password?("securepassword12")).to be(true)
    end

    it "[REQ-FIT-AUTH-002] updates password when at least 12 characters" do
      patch user_password_path, params: {
        user: {
          reset_password_token: reset_token,
          password: "brandnewpass99",
          password_confirmation: "brandnewpass99"
        }
      }

      expect(response).to redirect_to("/iniciar-sesion")
      follow_redirect!
      expect(flash[:notice]).to eq(I18n.t("auth.password.updated"))

      expect(user.reload.valid_password?("brandnewpass99")).to be(true)

      post user_session_path, params: { user: { email: user.email, password: "brandnewpass99" } }
      expect(response).to redirect_to(root_path)
    end
  end
end
