# frozen_string_literal: true

require "rails_helper"

# [REQ-FIT-BILL-001]
RSpec.describe "Parameter Filtering", type: :request do
  let(:parameter_filter) do
    ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
  end

  it "[REQ-FIT-BILL-001] filters sensitive payment and identification parameters" do
    sensitive_params = {
      card_number: "1234567812345678",
      holder_name: "Juan Perez",
      card_holder_name: "Juan Perez",
      mobile_number: "88888888",
      sinpe_mobile_number: "88888888",
      identification: "123456789",
      sinpe_identification: "123456789",
      card_cvv: "123"
    }

    filtered = parameter_filter.filter(sensitive_params)

    expect(filtered[:card_number]).to eq("[FILTERED]")
    expect(filtered[:holder_name]).to eq("[FILTERED]")
    expect(filtered[:card_holder_name]).to eq("[FILTERED]")
    expect(filtered[:mobile_number]).to eq("[FILTERED]")
    expect(filtered[:sinpe_mobile_number]).to eq("[FILTERED]")
    expect(filtered[:identification]).to eq("[FILTERED]")
    expect(filtered[:sinpe_identification]).to eq("[FILTERED]")
    expect(filtered[:card_cvv]).to eq("[FILTERED]")
  end
end
