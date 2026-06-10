# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::FeedbacksController", "[REQ-FIT-OPS-001]", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  let(:admin_user) { create_billing_user!(email: "admin-feedback@example.com") }
  let!(:feedback) do
    Feedback.create!(
      feedback_type: "suggestion",
      message: "Agregar modo oscuro al taller.",
      email: "user@example.com",
      status: "pending"
    )
  end

  before do
    admin_user.update!(admin: true)
  end

  describe "authorization" do
    it "[REQ-FIT-OPS-001] returns 404 for guests" do
      get admin_feedbacks_path
      expect(response).to have_http_status(:not_found)
    end

    it "[REQ-FIT-OPS-001] returns 404 for non-admin users" do
      user = create_billing_user!(email: "regular@example.com")
      sign_in_user!(user)

      get admin_feedbacks_path
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /admin/feedbacks" do
    before { sign_in_user!(admin_user) }

    it "[REQ-FIT-OPS-001] lists feedback for admins" do
      get admin_feedbacks_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Agregar modo oscuro")
    end

    it "[REQ-FIT-OPS-001] filters by status" do
      feedback.update!(status: "archived")

      get admin_feedbacks_path, params: { status: "pending" }

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Agregar modo oscuro")
    end

    it "[REQ-FIT-OPS-001] filters by feedback type" do
      get admin_feedbacks_path, params: { feedback_type: "suggestion" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Agregar modo oscuro")
    end
  end

  describe "PATCH /admin/feedbacks/:id" do
    before { sign_in_user!(admin_user) }

    it "[REQ-FIT-OPS-001] updates feedback status" do
      patch admin_feedback_path(feedback), params: { status: "reviewed" }

      expect(response).to redirect_to(admin_feedbacks_path)
      expect(feedback.reload.status).to eq("reviewed")
    end

    it "[REQ-FIT-OPS-001] redirects with an error when status is invalid" do
      patch admin_feedback_path(feedback), params: { status: "invalid" }

      expect(response).to redirect_to(admin_feedbacks_path)
      expect(flash[:alert]).to eq(I18n.t("feedback.flash.error"))
    end

    it "[REQ-FIT-OPS-001] redirects with an error when update fails" do
      allow_any_instance_of(Feedback).to receive(:update).and_return(false)

      patch admin_feedback_path(feedback), params: { status: "reviewed" }

      expect(response).to redirect_to(admin_feedbacks_path)
      expect(flash[:alert]).to eq(I18n.t("feedback.flash.error"))
    end
  end

  describe "DELETE /admin/feedbacks/:id" do
    before { sign_in_user!(admin_user) }

    it "[REQ-FIT-OPS-001] destroys feedback" do
      expect do
        delete admin_feedback_path(feedback)
      end.to change(Feedback, :count).by(-1)
    end
  end
end
