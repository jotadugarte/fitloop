# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Analytics & Users Routing", "[REQ-FIT-ANALYTICS-001]", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  let(:admin_user) { create_billing_user!(email: "admin-analytics@example.com") }
  let(:non_admin_user) { create_billing_user!(email: "user-analytics@example.com") }

  before do
    admin_user.update!(admin: true)
    non_admin_user.update!(admin: false)
  end

  describe "GET /admin/analytics" do
    context "when authenticated as admin" do
      it "returns 200 OK skeleton" do
        sign_in_user! admin_user
        get "/admin/analytics"
        expect(response).to have_http_status(:ok)
      end
    end

    context "when authenticated as non-admin" do
      it "returns 404 Not Found" do
        sign_in_user! non_admin_user
        get "/admin/analytics"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when unauthenticated" do
      it "returns 404 Not Found" do
        get "/admin/analytics"
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "GET /admin/usuarios" do
    context "when authenticated as admin" do
      it "returns 200 OK skeleton" do
        sign_in_user! admin_user
        get "/admin/usuarios"
        expect(response).to have_http_status(:ok)
      end
    end

    context "when authenticated as non-admin" do
      it "returns 404 Not Found" do
        sign_in_user! non_admin_user
        get "/admin/usuarios"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when unauthenticated" do
      it "returns 404 Not Found" do
        get "/admin/usuarios"
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
