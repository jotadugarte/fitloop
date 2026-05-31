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

        # Pending CRC card payment
        @payment_pending = Payment.create!(
          user: @user,
          status: "pending",
          payment_method: "card_crc",
          currency: "crc",
          amount: 1200,
          total_amount: 1200,
          purchaser_name: "Pending Client",
          purchaser_email: "pending@example.com",
          purpose: "single_download",
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_pending_1",
          onvo_mode: "test",
          gateway_status: "processing"
        )

        sign_in_user! admin_user
      end

      it "returns 200 OK and renders the admin layout" do
        get "/admin/ventas"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Jader Dugarte")
        expect(response.body).to include("John Doe")
        expect(response.body).to include("Pending Client")
      end

      it "filters by multiple statuses" do
        get "/admin/ventas", params: { status: ["succeeded", "failed"] }
        expect(response.body).to include("Jader Dugarte")
        expect(response.body).to include("John Doe")
        expect(response.body).not_to include("Pending Client")
      end

      it "filters by multiple payment methods" do
        get "/admin/ventas", params: { payment_method: ["sinpe_crc", "card_usd"] }
        expect(response.body).to include("Jader Dugarte")
        expect(response.body).to include("John Doe")
        expect(response.body).not_to include("Pending Client")
      end

      it "searches by purchaser name, email, or purchase reference" do
        get "/admin/ventas", params: { search: "Jader" }
        expect(response.body).to include("Jader Dugarte")
        expect(response.body).not_to include("John Doe")

        get "/admin/ventas", params: { search: "john@example.com" }
        expect(response.body).not_to include("Jader Dugarte")
        expect(response.body).to include("John Doe")
      end

      it "sorts transactions ascending when direction=asc is passed" do
        get "/admin/ventas", params: { direction: "asc" }
        expect(response).to have_http_status(:ok)
        
        jader_index = response.body.index("Jader Dugarte")
        pending_index = response.body.index("Pending Client")
        expect(jader_index).to be < pending_index
      end

      it "sorts transactions descending by default" do
        get "/admin/ventas"
        expect(response).to have_http_status(:ok)
        
        jader_index = response.body.index("Jader Dugarte")
        pending_index = response.body.index("Pending Client")
        expect(pending_index).to be < jader_index
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

        # Clear end_date bound to test start_date filter
        get "/admin/ventas", params: { start_date: 2.days.ago.to_date.to_s, end_date: "" }
        expect(response.body).to include("Jader Dugarte")
        expect(response.body).not_to include("Old Client")

        # Clear start_date bound to test end_date filter
        get "/admin/ventas", params: { end_date: 4.days.ago.to_date.to_s, start_date: "" }
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
          sinpe_transfer_identification: "123456789012",
          sinpe_transfer_mobile_number: "88888888"
        )
        sign_in_user! admin_user
        get "/admin/ventas/exportar"
      end

      it "returns 200 OK with CSV headers, UTF-8 BOM prefix, and Excel-safe string formatting" do
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/csv")
        expect(response.headers["Content-Disposition"]).to include("ventas-export-")
        
        # Verify BOM prefix (\uFEFF)
        expect(response.body.start_with?("\uFEFF")).to be(true)

        # Verify Excel formula wrapper in escaped CSV format
        expect(response.body).to include('"=""123456789012"""')
        expect(response.body).to include('"=""555555555555"""')
        expect(response.body).to include('"=""pi_export_ventas"""')
        expect(response.body).to include('"=""8314200000100"""') # cabys_code
      end
    end
  end

  describe "GET /admin/ventas/exportar-resumen [REQ-FIT-ADMIN-001]" do
    context "when unauthenticated" do
      it "returns 404 Not Found" do
        get "/admin/ventas/exportar-resumen"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when authenticated as admin" do
      before do
        @user = create_billing_user!(email: "client@example.com")
        
        # Create payments on same day/currency/method to test aggregation
        Payment.create!(
          user: @user, status: "succeeded", payment_method: "sinpe_crc", currency: "crc",
          amount: 1000, subtotal: 1000, total_amount: 1130, tax_amount: 130,
          paid_at: Time.current, gateway_provider: "onvo", onvo_payment_intent_id: "pi_1",
          onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download"
        )
        Payment.create!(
          user: @user, status: "succeeded", payment_method: "sinpe_crc", currency: "crc",
          amount: 2000, subtotal: 2000, total_amount: 2260, tax_amount: 260,
          paid_at: Time.current, gateway_provider: "onvo", onvo_payment_intent_id: "pi_2",
          onvo_mode: "test", gateway_status: "succeeded", purpose: "single_download"
        )
        
        # Create a failed one that should be ignored in summary
        Payment.create!(
          user: @user, status: "failed", payment_method: "sinpe_crc", currency: "crc",
          amount: 1000, subtotal: 1000, total_amount: 1130, tax_amount: 130,
          gateway_provider: "onvo", onvo_payment_intent_id: "pi_failed",
          onvo_mode: "test", gateway_status: "failed", purpose: "single_download"
        )

        sign_in_user! admin_user
        get "/admin/ventas/exportar-resumen"
      end

      it "returns 200 OK with summary headers, UTF-8 BOM, and aggregated totals" do
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/csv")
        expect(response.headers["Content-Disposition"]).to include("ventas-resumen-")
        
        # Verify BOM prefix (\uFEFF)
        expect(response.body.start_with?("\uFEFF")).to be(true)

        # Verify headers
        expect(response.body).to include("Fecha (Día),Moneda,Método de Pago,Cantidad de Ventas,Total Precio Lista,Total Descuento,Total Subtotal (Base),Total Impuesto (IVA 13%),Total Neto Cobrado")

        # Verify aggregation results (2 succeeded, total: 3390, subtotal: 3000, tax: 390)
        expect(response.body).to include("2") # count
        expect(response.body).to include("3000.0") # base sum
        expect(response.body).to include("390.0") # tax sum
        expect(response.body).to include("3390.0") # total net
      end
    end
  end
end
