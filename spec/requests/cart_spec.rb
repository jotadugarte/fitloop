# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cart (single-item) flow", "[REQ-FIT-BILL-001]", type: :request do
  describe "GET /carrito [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] renders an empty cart when no item exists (D6)" do
      begin_workspace_session!

      get "/carrito"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Carrito")
    end
  end

  describe "POST /carrito [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] creates a single_download cart for the latest downloadable run (D6)" do
      project = begin_workspace_session!
      run = project.nesting_runs.create!(status: "completed")
      project.update!(status: :completed)

      expect do
        post "/carrito", params: { kind: "single_download", nesting_run_id: run.id, currency_mode: "usd" }
      end.to change(Cart, :count).by(1)

      cart = Cart.last
      expect(cart.kind).to eq("single_download")
      expect(cart.nesting_run_id).to eq(run.id)
    end
  end
end

