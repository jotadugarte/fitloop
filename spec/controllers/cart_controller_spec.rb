# frozen_string_literal: true

require "rails_helper"

RSpec.describe CartController, "[REQ-FIT-BILL-001]" do
  include BillingModelHelpers

  subject(:cart_controller) { described_class.new }

  describe "#cart_line_summary" do
    it "returns the unknown label for blank sources" do
      expect(cart_controller.cart_line_summary(nil)).to eq(I18n.t("billing.cart.replace.line_unknown"))
    end

    it "summarizes plan lines from a cart record" do
      cart = Cart.new(kind: "plan", tier_months: 2)

      expect(cart_controller.cart_line_summary(cart)).to eq(
        I18n.t("billing.cart.replace.line_plan", months: 2)
      )
    end

    it "summarizes hash payloads from the pending-cart session" do
      summary = cart_controller.cart_line_summary({ "kind" => "plan", "tier_months" => 4 })

      expect(summary).to eq(I18n.t("billing.cart.replace.line_plan", months: 4))
    end

    it "summarizes download lines from a PendingCart value object" do
      pending = Billing::PendingCart.new(
        "kind" => "single_download",
        "nesting_run_id" => 42,
        "currency_mode" => "crc"
      )

      expect(cart_controller.cart_line_summary(pending)).to eq(
        I18n.t("billing.cart.replace.line_download")
      )
    end
  end

  describe "private cart helpers" do
    before do
      cart_controller.request = ActionDispatch::TestRequest.create
    end

    it "treats same-kind plan lines as different when tier months differ" do
      existing = Cart.new(kind: "plan", tier_months: 1)
      allow(cart_controller).to receive(:cart_kind_param).and_return("plan")
      cart_controller.params = ActionController::Parameters.new(tier_months: 2)

      expect(cart_controller.send(:different_cart_line?, existing)).to be(true)
    end

    it "treats same-kind download lines as different when nesting runs differ" do
      existing = Cart.new(kind: "single_download", nesting_run_id: 1)
      allow(cart_controller).to receive(:cart_kind_param).and_return("single_download")
      cart_controller.params = ActionController::Parameters.new(nesting_run_id: 2)

      expect(cart_controller.send(:different_cart_line?, existing)).to be(true)
    end

    it "does not persist guest tokens for signed-in users during upsert" do
      user = create_billing_user!
      session = ActionController::TestSession.new(cart_guest_token: "guest-token")
      allow(cart_controller).to receive(:session).and_return(session)
      allow(cart_controller).to receive(:current_user).and_return(user)
      allow(cart_controller).to receive(:cart_kind_param).and_return("plan")
      allow(cart_controller).to receive(:resolved_currency_mode).and_return("crc")
      cart_controller.params = ActionController::Parameters.new(tier_months: 1)
      allow(Billing::CartUpsert).to receive(:call)

      cart_controller.send(:upsert_cart!)

      expect(session[:cart_guest_token]).to eq("guest-token")
    end

    it "clears destroy when no cart exists" do
      session = ActionController::TestSession.new
      allow(cart_controller).to receive(:session).and_return(session)
      allow(cart_controller).to receive(:current_cart).and_return(nil)
      expect(cart_controller).to receive(:redirect_to).with(download_paywall_workshop_path)

      cart_controller.destroy
    end
  end
end
