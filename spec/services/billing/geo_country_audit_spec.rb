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

    it "[REQ-FIT-BILL-001] does not warn on non-billing paths" do
      allow(request).to receive(:path).and_return("/taller")

      expect(Rails.logger).not_to receive(:warn)

      described_class.record_resolution!(
        request: request,
        country_code: "US",
        source: :geolite2
      )
    end

    it "[REQ-FIT-BILL-001] does not warn when a billing country override is active" do
      allow(Billing::GeoPaymentDefaults).to receive(:country_override).and_return("CR")

      expect(Rails.logger).not_to receive(:warn)

      described_class.record_resolution!(
        request: request,
        country_code: "CR",
        source: :override
      )
    end

    it "[REQ-FIT-BILL-001] throttles duplicate warnings within the TTL window" do
      allow(Rails.cache).to receive(:read).and_return(true)

      expect(Rails.logger).not_to receive(:warn)

      described_class.record_resolution!(
        request: request,
        country_code: "US",
        source: :geolite2
      )
    end

    %i[override cloudflare user_time_zone session].each do |source|
      it "[REQ-FIT-BILL-001] labels #{source} in the missing Cloudflare warning" do
        label = described_class.send(:source_label, source)

        expect(Rails.logger).to receive(:warn).with(/#{Regexp.escape(label)}/)

        described_class.record_resolution!(
          request: request,
          country_code: "US",
          source: source
        )
      end
    end

    it "[REQ-FIT-BILL-001] labels unknown sources as the international USD default" do
      expect(Rails.logger).to receive(:warn).with(/default \(international USD\)/)

      described_class.record_resolution!(
        request: request,
        country_code: "US",
        source: :unknown
      )
    end

    it "[REQ-FIT-BILL-001] omits GeoLite2 install guidance when the MMDB is available" do
      allow(Billing::GeoLite2).to receive(:available?).and_return(true)

      expect(Rails.logger).to receive(:warn) do |message|
        expect(message).not_to include("Install GeoLite2")
      end

      described_class.record_resolution!(
        request: request,
        country_code: "US",
        source: :session
      )
    end
  end
end
