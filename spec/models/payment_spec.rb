# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payment, "[REQ-FIT-BILL-001]" do
  let(:user) { create_billing_user! }

  describe "associations [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] belongs to user" do
      expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
    end

    it "[REQ-FIT-BILL-001] optionally belongs to nesting_run for single-download payments" do
      expect(described_class.reflect_on_association(:nesting_run).macro).to eq(:belongs_to)
      expect(described_class.reflect_on_association(:nesting_run).options[:optional]).to be(true)
    end
  end

  describe "simulated checkout [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] records succeeded card USD payment with positive amount" do
      payment = described_class.create!(
        user: user,
        status: "succeeded",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2.0,
        purpose: "single_download",
        nesting_run: create_nesting_run!,
        paid_at: Time.current
      )

      expect(payment).to be_persisted
      expect(payment.amount).to be > 0
      expect(payment).to be_succeeded
    end

    it "[REQ-FIT-BILL-001] allows failed status without paid_at" do
      payment = described_class.new(
        user: user,
        status: "failed",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download"
      )

      expect(payment).to be_valid
    end
  end

  describe "ONVO gateway fields [REQ-FIT-BILL-001]" do
    def onvo_payment_attrs(overrides = {})
      {
        user: user,
        status: "pending",
        payment_method: "card_crc",
        currency: "crc",
        amount: 5000,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_test_abc123",
        onvo_mode: "test",
        gateway_status: "requires_payment_method"
      }.merge(overrides)
    end

    it "[REQ-FIT-BILL-001] persists gateway columns for pending ONVO payment without paid_at" do
      payment = described_class.create!(onvo_payment_attrs)

      expect(payment).to be_persisted
      expect(payment.gateway_provider).to eq("onvo")
      expect(payment.onvo_payment_intent_id).to eq("pi_test_abc123")
      expect(payment.onvo_mode).to eq("test")
      expect(payment.gateway_status).to eq("requires_payment_method")
      expect(payment.paid_at).to be_nil
      expect(payment).to be_pending
    end

    it "[REQ-FIT-BILL-001] requires gateway_status succeeded before ONVO payment can be succeeded" do
      payment = described_class.new(
        onvo_payment_attrs(
          status: "succeeded",
          gateway_status: "processing",
          paid_at: Time.current
        )
      )

      expect(payment).not_to be_valid
      expect(payment.errors[:gateway_status]).to be_present
    end

    it "[REQ-FIT-BILL-001] accepts succeeded ONVO payment when gateway_status is succeeded" do
      payment = described_class.new(
        onvo_payment_attrs(
          status: "succeeded",
          gateway_status: "succeeded",
          paid_at: Time.current
        )
      )

      expect(payment).to be_valid
    end

    it "[REQ-FIT-BILL-001] allows legacy succeeded payment without gateway fields (simulate)" do
      payment = described_class.new(
        user: user,
        status: "succeeded",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2.0,
        purpose: "single_download",
        paid_at: Time.current
      )

      expect(payment).to be_valid
      expect(payment.gateway_provider).to be_nil
    end
  end

  describe "payment snapshot fields [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] persists purchaser and amount breakdown for succeeded and failed payments (D20, D24)" do
      payment = described_class.create!(
        user: user,
        status: "failed",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2.5,
        purpose: "single_download",
        purchaser_name: "Ada Lovelace",
        purchaser_email: "ada@example.com",
        product_description: "Descarga única",
        list_price: 2.5,
        discount_amount: 0.5,
        subtotal: 2.5,
        tax_amount: 0.0,
        total_amount: 2.0
      )

      expect(payment.purchaser_name).to eq("Ada Lovelace")
      expect(payment.purchaser_email).to eq("ada@example.com")
      expect(payment.product_description).to eq("Descarga única")
      expect(payment.total_amount).to eq(2.0)
    end
  end
end
