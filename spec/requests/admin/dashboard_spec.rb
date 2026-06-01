# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Dashboard", "[REQ-FIT-ADMIN-001]", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  let(:admin_user) { create_billing_user!(email: "admin@example.com") }
  let(:non_admin_user) { create_billing_user!(email: "user@example.com") }

  before do
    admin_user.update!(admin: true)
    non_admin_user.update!(admin: false)
  end

  describe "GET /admin [REQ-FIT-ADMIN-001]" do
    context "when authenticated as admin" do
      before do
        sign_in_user! admin_user
        get "/admin"
      end

      it "returns 200 OK" do
        expect(response).to have_http_status(:ok)
      end

      it "displays the admin dashboard options for Ventas and Analytics" do
        expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.dashboard.ventas.title")))
        expect(response.body).to include(ERB::Util.html_escape(I18n.t("admin.dashboard.analytics.title")))
        expect(response.body).to include(I18n.t("admin.dashboard.active_badge"))
      end
    end

    context "when authenticated as a non-admin user" do
      it "returns 404 Not Found" do
        sign_in_user! non_admin_user
        get "/admin"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when unauthenticated" do
      it "returns 404 Not Found" do
        get "/admin"
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET relative admin paths redirects" do
    context "when authenticated as admin" do
      before do
        sign_in_user! admin_user
      end

      it "redirects /taller/admin to /admin" do
        get "/taller/admin"
        expect(response).to redirect_to("/admin")
      end

      it "redirects /mi-cuenta/admin to /admin" do
        get "/mi-cuenta/admin"
        expect(response).to redirect_to("/admin")
      end
    end

    context "when authenticated as a non-admin user" do
      before do
        sign_in_user! non_admin_user
      end

      it "redirects /taller/admin to /admin (which yields 404)" do
        get "/taller/admin"
        expect(response).to redirect_to("/admin")
        follow_redirect!
        expect(response).to have_http_status(:not_found)
      end

      it "redirects /mi-cuenta/admin to /admin (which yields 404)" do
        get "/mi-cuenta/admin"
        expect(response).to redirect_to("/admin")
        follow_redirect!
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
