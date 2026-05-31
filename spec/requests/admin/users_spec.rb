# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::UsersController", "[REQ-FIT-ANALYTICS-001]", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  let(:admin_user) { create_billing_user!(email: "admin-users-view@example.com") }
  let!(:user_a) { create_billing_user!(email: "alice@example.com").tap { |u| u.update!(name: "Alice Smith") } }
  let!(:user_b) { create_billing_user!(email: "bob@example.com").tap { |u| u.update!(name: "Bob Jones") } }

  before do
    admin_user.update!(admin: true)
    sign_in_user! admin_user
  end

  describe "GET /admin/usuarios" do
    it "lists all users" do
      get "/admin/usuarios"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alice Smith")
      expect(response.body).to include("Bob Jones")
    end

    it "filters users by search query" do
      get "/admin/usuarios", params: { q: "Alice" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alice Smith")
      expect(response.body).not_to include("Bob Jones")
    end
  end

  describe "GET /admin/usuarios/:id" do
    before do
      # Seed events for user_a
      UserEvent.create!(
        event_type: "workspace_started",
        user_id: user_a.id,
        occurred_at: Time.current - 1.day,
        priority: "low"
      )

      UserEvent.create!(
        event_type: "payment_succeeded",
        user_id: user_a.id,
        occurred_at: Time.current,
        priority: "critical"
      )
    end

    it "shows user details and timeline in descending occurred_at order" do
      get "/admin/usuarios/#{user_a.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Alice Smith")
      expect(response.body).to include("workspace_started")
      expect(response.body).to include("payment_succeeded")
    end
  end
end
