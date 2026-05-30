# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::GeoCountryAudit, "[REQ-FIT-BILL-001]", type: :service do
  let(:request) do
    instance_double(
      ActionDispatch::Request,
      path: "/checkout",
      headers: {}
    )
  end

  before do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
    allow(Rails).to receive(:logger).and_return(instance_double(Logger, warn: nil))
    allow(Rails.cache).to receive(:read).and_return(nil)
    allow(Rails.cache).to receive(:write)
    allow(Billing::GeoPaymentDefaults).to receive(:country_override).and_return(nil)
    allow(Billing::GeoPaymentDefaults).to receive(:cloudflare_country_code).with(request).and_return(nil)
    allow(Billing::GeoLite2).to receive(:available?).and_return(false)
  end

  describe ".record_resolution! [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] warns when CF-IPCountry is missing on billing paths in production" do
      expect(Rails.logger).to receive(:warn).with(/CF-IPCountry missing/)

      described_class.record_resolution!(
        request: request,
        country_code: "US",
        source: :geolite2
      )
    end

    it "[REQ-FIT-BILL-001] does not warn when Cloudflare country is present" do
      allow(Billing::GeoPaymentDefaults).to receive(:cloudflare_country_code).with(request).and_return("CR")

      expect(Rails.logger).not_to receive(:warn)

      described_class.record_resolution!(
        request: request,
        country_code: "CR",
        source: :cloudflare
      )
    end

    it "[REQ-FIT-BILL-001] does not warn outside production" do
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))

      expect(Rails.logger).not_to receive(:warn)

      described_class.record_resolution!(
        request: request,
        country_code: "US",
        source: :geolite2
      )
    end
  end
end
