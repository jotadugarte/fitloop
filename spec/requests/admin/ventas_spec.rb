# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Admin::Ventas", "[REQ-FIT-ADMIN-001]", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  let(:admin_user) { create_billing_user!(email: "admin@example.com") }
  let(:non_admin_user) { create_billing_user!(email: "user@example.com") }

  before do
    admin_user.update!(admin: true)
    non_admin_user.update!(admin: false)
  end

  describe "GET /admin/ventas [REQ-FIT-ADMIN-001]" do
    context "when unauthenticated" do
      it "returns 404 Not Found" do
        get "/admin/ventas"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when authenticated as a non-admin user" do
      it "returns 404 Not Found" do
        sign_in_user! non_admin_user
        get "/admin/ventas"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when authenticated as admin" do
      before do
        @user = create_billing_user!(email: "client@example.com")
        
        # Succeeded CRC payment
        @payment_succ = Payment.create!(
          user: @user,
          status: "succeeded",
          payment_method: "sinpe_crc",
          currency: "crc",
          amount: 5000,
          total_amount: 5000,
          purchaser_name: "Jader Dugarte",
          purchaser_email: "jader@example.com",
          purpose: "single_download",
          paid_at: Time.current,
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_succ_1",
          onvo_mode: "test",
          gateway_status: "succeeded",
          purchase_reference: "123456789012"
        )

        # Failed USD payment
        @payment_fail = Payment.create!(
          user: @user,
          status: "failed",
          payment_method: "card_usd",
          currency: "usd",
          amount: 10,
          total_amount: 10,
          purchaser_name: "John Doe",
          purchaser_email: "john@example.com",
          purpose: "plan_subscription",
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_fail_1",
          onvo_mode: "test",
          gateway_status: "failed",
          purchase_reference: "987654321098"
        )

        sign_in_user! admin_user
      end

      it "returns 200 OK and renders the admin layout" do
        get "/admin/ventas"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Jader Dugarte")
        expect(response.body).to include("John Doe")
      end

      it "filters by status" do
        get "/admin/ventas", params: { status: "succeeded" }
        expect(response.body).to include("Jader Dugarte")
        expect(response.body).not_to include("John Doe")

        get "/admin/ventas", params: { status: "failed" }
        expect(response.body).not_to include("Jader Dugarte")
        expect(response.body).to include("John Doe")
      end

      it "searches by purchaser name, email, or purchase reference" do
        get "/admin/ventas", params: { search: "Jader" }
        expect(response.body).to include("Jader Dugarte")
        expect(response.body).not_to include("John Doe")

        get "/admin/ventas", params: { search: "john@example.com" }
        expect(response.body).not_to include("Jader Dugarte")
        expect(response.body).to include("John Doe")

        get "/admin/ventas", params: { search: "123456789012" }
        expect(response.body).to include("Jader Dugarte")
        expect(response.body).not_to include("John Doe")
      end

      it "filters by date range" do
        # Payment created 5 days ago
        @payment_old = Payment.create!(
          user: @user,
          status: "succeeded",
          payment_method: "card_usd",
          currency: "usd",
          amount: 20,
          total_amount: 20,
          purchaser_name: "Old Client",
          purchaser_email: "old@example.com",
          purpose: "plan_subscription",
          paid_at: 5.days.ago,
          created_at: 5.days.ago,
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_old_1",
          onvo_mode: "test",
          gateway_status: "succeeded"
        )

        get "/admin/ventas", params: { start_date: 2.days.ago.to_date.to_s }
        expect(response.body).to include("Jader Dugarte")
        expect(response.body).not_to include("Old Client")

        get "/admin/ventas", params: { end_date: 4.days.ago.to_date.to_s }
        expect(response.body).not_to include("Jader Dugarte")
        expect(response.body).to include("Old Client")
      end
    end
  end

  describe "GET /admin/ventas/exportar [REQ-FIT-ADMIN-001]" do
    context "when unauthenticated" do
      it "returns 404 Not Found" do
        get "/admin/ventas/exportar"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when authenticated as a non-admin user" do
      it "returns 404 Not Found" do
        sign_in_user! non_admin_user
        get "/admin/ventas/exportar"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when authenticated as admin" do
      before do
        @user = create_billing_user!(email: "client@example.com")
        @payment = Payment.create!(
          user: @user,
          status: "succeeded",
          payment_method: "sinpe_crc",
          currency: "crc",
          amount: 5000,
          total_amount: 5000,
          purchaser_name: "Costa Rica Client",
          purchaser_email: "crc_client@example.com",
          purpose: "single_download",
          paid_at: Time.current,
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_export_ventas",
          onvo_mode: "test",
          gateway_status: "succeeded",
          purchase_reference: "555555555555",
          sinpe_transfer_identification: "123456",
          sinpe_transfer_mobile_number: "88888888"
        )
        sign_in_user! admin_user
        get "/admin/ventas/exportar"
      end

      it "returns 200 OK with CSV headers and invoicing fields including cabys_code" do
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/csv")
        expect(response.headers["Content-Disposition"]).to include("ventas-export-")
        
        headers = ["ID", "Fecha", "Usuario ID", "Email Comprador", "Nombre Comprador", "Identificación SINPE", "Teléfono SINPE", "Referencia", "ID Intento de Pago", "Método de Pago", "Estado", "Monto Lista", "Descuento", "Subtotal", "Impuesto (IVA)", "Monto Total", "Moneda", "Código CAByS"]
        headers.each do |h|
          expect(response.body).to include(h)
        end

        expect(response.body).to include("Costa Rica Client")
        expect(response.body).to include("crc_client@example.com")
        expect(response.body).to include("555555555555")
        expect(response.body).to include("8314200000100") # cabys_code
        expect(response.body).to include("123456") # sinpe id
        expect(response.body).to include("88888888") # sinpe mobile
      end
    end
  end
end
