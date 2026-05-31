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

    it "maps plan_N_months from product_description" do
      payment = Payment.new(
        user: user, purpose: "plan_subscription", product_description: "plan_2_months"
      )
      expect(described_class.product_label(payment)).to eq("Suscripción mensual - Plan de 2 meses")
    end
  end
end
