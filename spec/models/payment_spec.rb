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
end
