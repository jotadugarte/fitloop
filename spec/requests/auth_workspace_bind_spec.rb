# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Auth preserves workspace project bind", type: :request do
  def registration_params(overrides = {})
    {
      user: {
        email: "signup@example.com",
        password: "securepassword12",
        password_confirmation: "securepassword12",
        name: "Pat Smith",
        terms_accepted: "1",
        time_zone: "America/Costa_Rica"
      }.merge(overrides)
    }
  end

  def create_confirmed_user!(email: "auth@example.com")
    User.new(
      email: email,
      password: "securepassword12",
      password_confirmation: "securepassword12",
      name: "Auth User",
      terms_accepted_at: Time.current,
      terms_version: "v1-placeholder",
      time_zone: "America/Costa_Rica",
      confirmed_at: Time.current
    ).tap(&:skip_confirmation_notification!).tap(&:save!)
  end

  describe "POST /iniciar-sesion [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] returns to project#show and keeps session bind (D18)" do
      project = begin_workspace_session!
      user = create_confirmed_user!

      get new_user_session_path
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

      expect(response).to redirect_to(project_path(project))
      expect(session[Workspace::SESSION_KEY]).to eq(project.id)

      get project_path(project)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t("projects.show.session_title"))
    end
  end

  describe "POST /crear-cuenta [REQ-FIT-AUTH-002]" do
    it "[REQ-FIT-AUTH-002] returns to project#show and keeps session bind (D18)" do
      project = begin_workspace_session!

      get new_user_registration_path
      post user_registration_path, params: registration_params

      expect(response).to redirect_to(project_path(project))
      expect(session[Workspace::SESSION_KEY]).to eq(project.id)

      get project_path(project)
      expect(response).to have_http_status(:ok)
    end
  end
end
