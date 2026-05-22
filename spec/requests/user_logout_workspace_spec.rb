# frozen_string_literal: true

require "rails_helper"

RSpec.describe "User logout discards workspace", type: :request do
  def create_confirmed_user!(email: "logout@example.com")
    User.new(
      email: email,
      password: "securepassword12",
      password_confirmation: "securepassword12",
      name: "Logout User",
      terms_accepted_at: Time.current,
      terms_version: "v1-placeholder",
      time_zone: "America/Costa_Rica",
      confirmed_at: Time.current
    ).tap(&:skip_confirmation_notification!).tap(&:save!)
  end

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "DELETE /cerrar-sesion [REQ-FIT-AUTH-002]" do
    context "with active workspace project (D19)" do
      it "[REQ-FIT-AUTH-002] requires confirmation before signing out" do
        user = create_confirmed_user!
        project = begin_workspace_session!
        sign_in_user! user

        expect(session[Workspace::SESSION_KEY]).to eq(project.id)

        delete destroy_user_session_path

        expect(response).to have_http_status(:ok)
        expect(response.body).to include(I18n.t("auth.sign_out.confirm_warning"))
        expect(Project.exists?(project.id)).to be(true)
        expect(session[Workspace::SESSION_KEY]).to eq(project.id)

        get edit_user_registration_path
        expect(response).to have_http_status(:ok)
      end

      it "[REQ-FIT-AUTH-002] discards workspace and signs out when discard is confirmed (D19)" do
        user = create_confirmed_user!
        project = begin_workspace_session!
        sign_in_user! user

        delete destroy_user_session_path, params: { confirm_workspace_discard: "1" }

        expect(response).to redirect_to(root_path)
        expect(Project.exists?(project.id)).to be(false)
        expect(session[Workspace::SESSION_KEY]).to be_nil

        get edit_user_registration_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "without workspace bind" do
      it "[REQ-FIT-AUTH-002] signs out immediately without confirmation" do
        user = create_confirmed_user!
        sign_in_user! user

        delete destroy_user_session_path

        expect(response).to redirect_to(root_path)

        get edit_user_registration_path
        expect(response).to redirect_to(new_user_session_path)
      end

      it "[REQ-FIT-AUTH-002] signs out from Mi cuenta without confirmation when no active project" do
        I18n.with_locale(:es) do
          user = create_confirmed_user!
          sign_in_user! user

          delete destroy_user_session_path

          follow_redirect!
          expect(response.body).to include(I18n.t("devise.sessions.user.signed_out"))
          expect(response.body).not_to include("translation missing")
        end
      end
    end
  end
end
