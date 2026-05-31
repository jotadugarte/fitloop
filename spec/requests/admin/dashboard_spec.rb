# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin Dashboard", "[REQ-FIT-ADMIN-001]", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "GET /admin [REQ-FIT-ADMIN-001]" do
    let(:admin_user) { create_billing_user!(email: "admin@example.com") }
    let(:non_admin_user) { create_billing_user!(email: "user@example.com") }

    before do
      admin_user.update!(admin: true)
      non_admin_user.update!(admin: false)
    end

    context "when authenticated as admin" do
      it "returns 200 OK" do
        sign_in_user! admin_user
        get "/admin"
        expect(response).to have_http_status(:ok)
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
end
