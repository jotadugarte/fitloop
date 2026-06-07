# frozen_string_literal: true

require "rails_helper"

RSpec.describe Admin::VentasHelper, "[REQ-FIT-ADMIN-001]", type: :helper do
  describe "#admin_payment_purpose_label" do
    it "delegates purpose labels to PaymentDisplayLabels" do
      expect(helper.admin_payment_purpose_label("single_download")).to eq(
        Admin::PaymentDisplayLabels.purpose_label("single_download")
      )
    end
  end

  describe "#admin_form150_export_params" do
    it "defaults status to succeeded when the query omits status" do
      expect(helper.admin_form150_export_params({})).to eq("status" => [ "succeeded" ])
    end

    it "preserves an explicit status filter" do
      params = { "status" => [ "failed" ] }
      expect(helper.admin_form150_export_params(params)).to eq(params)
    end

    it "preserves an explicit status filter with symbol key" do
      params = { status: [ "pending" ] }
      expect(helper.admin_form150_export_params(params)).to eq("status" => [ "pending" ])
    end
  end
end
