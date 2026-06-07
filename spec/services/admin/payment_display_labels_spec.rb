# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::PaymentDisplayLabels, "[REQ-FIT-ADMIN-001]", type: :service do
  describe ".product_label" do
    let(:user) { create_billing_user!(email: "labels@example.com") }

    it "maps single_download to Spanish invoicing label" do
      payment = Payment.new(
        user: user, purpose: "single_download", product_description: "single_download"
      )
      expect(described_class.product_label(payment)).to eq("Procesamiento de anidado DXF")
    end

    it "maps single_download from purpose when product_description is blank" do
      payment = Payment.new(user: user, purpose: "single_download", product_description: "")
      expect(described_class.product_label(payment)).to eq("Procesamiento de anidado DXF")
    end

    it "maps plan_N_months from product_description" do
      payment = Payment.new(
        user: user, purpose: "plan_subscription", product_description: "plan_2_months"
      )
      expect(described_class.product_label(payment)).to eq("Suscripción mensual - Plan de 2 meses")
    end

    it "falls back to purpose label when product_description does not match plan pattern" do
      payment = Payment.new(
        user: user, purpose: "plan_subscription", product_description: "unknown_description"
      )
      expect(described_class.product_label(payment)).to eq("Plan")
    end
  end

  describe ".payment_method_label" do
    it "returns translated label for known method" do
      expect(described_class.payment_method_label("sinpe_crc")).to eq("SINPE Móvil")
    end

    it "returns uppercase string for unknown method" do
      expect(described_class.payment_method_label("custom_pay")).to eq("CUSTOM PAY")
    end
  end

  describe ".status_label" do
    it "returns translated label for known status" do
      expect(described_class.status_label("succeeded")).to eq("Exitoso")
    end

    it "returns capitalized string for unknown status" do
      expect(described_class.status_label("unknown_status")).to eq("Unknown_status")
    end
  end

  describe ".purpose_label" do
    it "returns translated label for known purpose" do
      expect(described_class.purpose_label("single_download")).to eq("Descarga suelta")
    end

    it "returns humanized string for unknown purpose" do
      expect(described_class.purpose_label("unknown_purpose")).to eq("Unknown purpose")
    end
  end
end

