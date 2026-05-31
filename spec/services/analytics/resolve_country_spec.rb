# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::ResolveCountry, "[REQ-FIT-ANALYTICS-001]" do
  let(:request) { double("Request", remote_ip: "186.15.123.4", headers: {}, get_header: nil) }

  describe ".call" do
    context "when CF-IPCountry header is present" do
      it "returns the country from the Cloudflare header" do
        allow(request.headers).to receive(:[]).with("CF-IPCountry").and_return("CR")
        expect(described_class.call(request)).to eq("CR")
      end

      it "falls back to HTTP_CF_IPCOUNTRY header if CF-IPCountry is nil" do
        allow(request.headers).to receive(:[]).with("CF-IPCountry").and_return(nil)
        allow(request).to receive(:get_header).with("HTTP_CF_IPCOUNTRY").and_return("US")
        expect(described_class.call(request)).to eq("US")
      end
    end

    context "when CF-IPCountry is absent" do
      before do
        allow(request.headers).to receive(:[]).with("CF-IPCountry").and_return(nil)
        allow(request).to receive(:get_header).with("HTTP_CF_IPCOUNTRY").and_return(nil)
      end

      it "falls back to GeoLite2 lookup using request.remote_ip" do
        expect(Billing::GeoLite2).to receive(:country_code_for_ip).with("186.15.123.4").and_return("CR")
        expect(described_class.call(request)).to eq("CR")
      end

      it "returns nil if both Cloudflare header and GeoLite2 lookup fail" do
        expect(Billing::GeoLite2).to receive(:country_code_for_ip).with("186.15.123.4").and_return(nil)
        expect(described_class.call(request)).to be_nil
      end
    end

    context "when request is nil" do
      it "returns nil" do
        expect(described_class.call(nil)).to be_nil
      end
    end
  end
end
