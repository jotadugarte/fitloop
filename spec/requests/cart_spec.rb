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
end

