# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cart (single-item) flow", "[REQ-FIT-BILL-001]", type: :request do
  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "GET /carrito [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] redirects to paywall when empty (D6)" do
      begin_workspace_session!

      get "/carrito"

      expect(response).to redirect_to("/taller/descarga-pago")
    end

    it "[REQ-FIT-BILL-001] redirects to checkout when a line exists (D6)" do
      user = create_billing_user!
      project = begin_workspace_session!
      run = project.nesting_runs.create!(status: "completed")
      project.update!(status: :completed)
      sign_in_user! user

      Cart.create!(
        kind: "single_download",
        nesting_run: run,
        currency_mode: "crc",
        overage: false,
        user: user,
        list_price_cents: 1200,
        sinpe_price_cents: 1000
      )

      get "/carrito"

      expect(response).to redirect_to("/checkout")
    end
  end

  describe "POST /carrito [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] creates a line and redirects to checkout (D6)" do
      user = create_billing_user!
      project = begin_workspace_session!
      run = project.nesting_runs.create!(status: "completed")
      project.update!(status: :completed)
      sign_in_user! user

      expect do
        post "/carrito",
             params: { kind: "single_download", nesting_run_id: run.id },
             headers: { "CF-IPCountry" => "CR" }
      end.to change(Cart, :count).by(1)

      expect(response).to redirect_to("/checkout")
      cart = Cart.last
      expect(cart.kind).to eq("single_download")
      expect(cart.nesting_run_id).to eq(run.id)
    end

    it "[REQ-FIT-BILL-001] replaces the existing single line (D6)" do
      user = create_billing_user!
      project = begin_workspace_session!
      run1 = project.nesting_runs.create!(status: "completed")
      run2 = project.nesting_runs.create!(status: "completed")
      project.update!(status: :completed)
      sign_in_user! user

      post "/carrito", params: { kind: "single_download", nesting_run_id: run1.id }, headers: { "CF-IPCountry" => "CR" }
      expect(Cart.count).to eq(1)

      post "/carrito", params: { kind: "single_download", nesting_run_id: run2.id }, headers: { "CF-IPCountry" => "CR" }

      expect(Cart.count).to eq(1)
      expect(Cart.last.nesting_run_id).to eq(run2.id)
      expect(response).to redirect_to("/checkout")
    end
  end

  describe "DELETE /carrito [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] clears the line and returns to paywall (D6)" do
      user = create_billing_user!
      project = begin_workspace_session!
      run = project.nesting_runs.create!(status: "completed")
      project.update!(status: :completed)
      sign_in_user! user

      post "/carrito", params: { kind: "single_download", nesting_run_id: run.id }, headers: { "CF-IPCountry" => "CR" }

      expect do
        delete "/carrito"
      end.to change(Cart, :count).by(-1)

      expect(response).to redirect_to("/taller/descarga-pago")
    end
  end
end
