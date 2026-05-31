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
        @user1 = create_billing_user!(email: "client1@example.com")
        @user2 = create_billing_user!(email: "client2@example.com")

        # Succeeded CRC payment
        Payment.create!(
          user: @user1,
          status: "succeeded",
          payment_method: "sinpe_crc",
          currency: "crc",
          amount: 5000,
          total_amount: 5000,
          purpose: "single_download",
          paid_at: Time.current,
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_crc_succ",
          onvo_mode: "test",
          gateway_status: "succeeded",
          purchase_reference: "111111111111"
        )

        # Succeeded USD payment
        Payment.create!(
          user: @user2,
          status: "succeeded",
          payment_method: "card_usd",
          currency: "usd",
          amount: 25,
          total_amount: 25,
          purpose: "plan_subscription",
          paid_at: Time.current,
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_usd_succ",
          onvo_mode: "test",
          gateway_status: "succeeded",
          purchase_reference: "222222222222"
        )

        # Failed CRC payment
        Payment.create!(
          user: @user1,
          status: "failed",
          payment_method: "card_crc",
          currency: "crc",
          amount: 1500,
          total_amount: 1500,
          purpose: "single_download",
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_crc_fail",
          onvo_mode: "test",
          gateway_status: "failed",
          purchase_reference: "333333333333"
        )

        create_nesting_run!
        create_nesting_run!

        sign_in_user! admin_user
        get "/admin"
      end

      it "returns 200 OK" do
        expect(response).to have_http_status(:ok)
      end

      it "displays total revenue formatted correctly for both CRC and USD" do
        expect(response.body).to include("₡5,000")
        expect(response.body).to include("$25.00")
      end

      it "displays transaction counts for succeeded, failed, and pending status" do
        expect(response.body).to include("2 OK")
        expect(response.body).to include("1 Fallidas")
        expect(response.body).to include("0 Pendientes")
      end

      it "displays total registered users" do
        expect(response.body).to include("4")
      end

      it "displays total nesting runs" do
        expect(response.body).to include("2")
      end

      it "lists recent payments in the table" do
        expect(response.body).to include("111111111111")
        expect(response.body).to include("222222222222")
        expect(response.body).to include("333333333333")
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

  describe "GET /admin/exportar-ventas" do
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
          purchaser_email: "client@example.com",
          purchaser_name: "Client Name",
          purpose: "single_download",
          paid_at: Time.current,
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_export",
          onvo_mode: "test",
          gateway_status: "succeeded",
          purchase_reference: "444444444444"
        )
        sign_in_user! admin_user
        get "/admin/exportar-ventas"
      end

      it "returns 200 OK with CSV Content-Type" do
        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/csv")
        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.headers["Content-Disposition"]).to include("ventas-fitloop-")
      end

      it "contains correct CSV header" do
        expect(response.body).to include("ID,Fecha,Usuario ID,Email Comprador,Nombre Comprador,Concepto,Metodo de Pago,Moneda,Subtotal,Descuento,Impuesto,Total,Estado,Referencia,Identificacion SINPE")
      end

      it "contains the payment data" do
        expect(response.body).to include("444444444444")
        expect(response.body).to include("client@example.com")
        expect(response.body).to include("Client Name")
        expect(response.body).to include("sinpe_crc")
        expect(response.body).to include("succeeded")
      end
    end

    context "when authenticated as a non-admin user" do
      it "returns 404 Not Found" do
        sign_in_user! non_admin_user
        get "/admin/exportar-ventas"
        expect(response).to have_http_status(:not_found)
      end
    end

    context "when unauthenticated" do
      it "returns 404 Not Found" do
        get "/admin/exportar-ventas"
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
