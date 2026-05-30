# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::GeoLite2, "[REQ-FIT-BILL-001]", type: :service do
  after do
    described_class.remove_instance_variable(:@client) if described_class.instance_variable_defined?(:@client)
  end

  describe ".country_code_for_ip [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] returns nil for loopback without a database" do
      expect(described_class.country_code_for_ip("127.0.0.1")).to be_nil
    end

    it "[REQ-FIT-BILL-001] returns nil when MMDB path is not configured" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GEOLITE2_COUNTRY_MMDB_PATH").and_return(nil)

      expect(described_class.country_code_for_ip("8.8.8.8")).to be_nil
      expect(described_class.available?).to be(false)
    end

    it "[REQ-FIT-BILL-001] uses MaxMindDB client when database path is set" do
      country = Struct.new(:iso_code).new("US")
      lookup = Struct.new(:found?, :country).new(true, country)
      maxmind = instance_double(MaxMindDB::Client, lookup: lookup)

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GEOLITE2_COUNTRY_MMDB_PATH").and_return("/tmp/GeoLite2-Country.mmdb")
      allow(File).to receive(:file?).with("/tmp/GeoLite2-Country.mmdb").and_return(true)
      allow(MaxMindDB).to receive(:new).with("/tmp/GeoLite2-Country.mmdb").and_return(maxmind)

      described_class.remove_instance_variable(:@client) if described_class.instance_variable_defined?(:@client)

      expect(described_class.country_code_for_ip("8.8.8.8")).to eq("US")
      expect(described_class.available?).to be(true)
    end
  end
end
