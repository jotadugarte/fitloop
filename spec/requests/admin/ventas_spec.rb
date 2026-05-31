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
          product_description: "single_download",
          paid_at: Time.current,
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_succ_1",
          onvo_mode: "test",
          gateway_status: "succeeded",
          purchase_reference: "123456789012"
        )

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
          product_description: "plan_2_months",
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_fail_1",
          onvo_mode: "test",
          gateway_status: "failed",
          purchase_reference: "987654321098"
        )

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
          product_description: "single_download",
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
        expect(response.body).to include("Procesamiento de anidado DXF")
        expect(response.body).to include("Declaración CRC — ventas locales (IVA 13%)")
        expect(response.body).to include("Declaración USD — factura de exportación")
        expect(response.body).to include("Transacciones en colones (CRC)")
        expect(response.body).to include("Transacciones en dólares (USD)")
      end

      it "filters by multiple statuses" do
        get "/admin/ventas", params: { status: [ "succeeded", "failed" ] }
        expect(response.body).to include("Jader Dugarte")
        expect(response.body).to include("John Doe")
        expect(response.body).not_to include("Pending Client")
      end

      it "filters by multiple payment methods" do
        get "/admin/ventas", params: { payment_method: [ "sinpe_crc", "card_usd" ] }
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

      it "does not treat percent as ILIKE wildcard in search" do
        get "/admin/ventas", params: { search: "%" }
        expect(response.body).not_to include("Jader Dugarte")
        expect(response.body).not_to include("John Doe")
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
          product_description: "plan_1_months",
          paid_at: 5.days.ago,
          created_at: 5.days.ago,
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_old_1",
          onvo_mode: "test",
          gateway_status: "succeeded"
        )

        get "/admin/ventas", params: { start_date: 2.days.ago.to_date.to_s, end_date: "" }
        expect(response.body).to include("Jader Dugarte")
        expect(response.body).not_to include("Old Client")

        get "/admin/ventas", params: { end_date: 4.days.ago.to_date.to_s, start_date: "" }
        expect(response.body).not_to include("Jader Dugarte")
        expect(response.body).to include("Old Client")
      end
    end
  end

  describe "GET /admin/ventas/exportar [REQ-FIT-ADMIN-001]" do
    it "returns 404 for removed CSV export route" do
      sign_in_user! admin_user
      get "/admin/ventas/exportar"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /admin/ventas/exportar-resumen [REQ-FIT-ADMIN-001]" do
    it "returns 404 for removed CSV summary export route" do
      sign_in_user! admin_user
      get "/admin/ventas/exportar-resumen"
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /admin/ventas/exportar-xlsx [REQ-FIT-ADMIN-001]" do
    context "when unauthenticated" do
      it "returns 404 Not Found" do
        get "/admin/ventas/exportar-xlsx"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when authenticated as admin" do
      before do
        @user = create_billing_user!(email: "client@example.com")
        Payment.create!(
          user: @user,
          status: "succeeded",
          payment_method: "sinpe_crc",
          currency: "crc",
          amount: 5000,
          total_amount: 5650,
          subtotal: 5000,
          tax_amount: 650,
          purchaser_name: "Ana Torres",
          purchaser_email: "ana@example.com",
          purpose: "single_download",
          product_description: "single_download",
          paid_at: Time.current,
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_xlsx_test",
          onvo_mode: "test",
          gateway_status: "succeeded",
          purchase_reference: "777777777777"
        )
        sign_in_user! admin_user
        get "/admin/ventas/exportar-xlsx"
      end

      it "returns 200 OK with xlsx Content-Type and attachment disposition" do
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("spreadsheetml.sheet")
        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.headers["Content-Disposition"]).to include(".xlsx")
      end

      it "returns a valid xlsx binary (PK ZIP header)" do
        expect(response.body.bytes.first(2)).to eq([ 0x50, 0x4B ])
      end
    end
  end
end
