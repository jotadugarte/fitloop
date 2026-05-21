# frozen_string_literal: true

require "rails_helper"
require "fitloop_home_verifier"

RSpec.describe FitloopHomeVerifier do
  REQUIRED_LOCALE_FILES = %w[en es es_panic].freeze

  describe "#check_i18n [REQ-FIT-UI-005]" do
    it "requires en, es, and es_panic locale files" do
      verifier = described_class.new

      expect(verifier.send(:check_i18n)).to eq([])
    end

    it "reports missing es_panic locale file" do
      path = Rails.root.join("config/locales/es_panic.yml")
      backup = path.read
      path.delete

      errors = described_class.new.send(:check_i18n)
      expect(errors).to include("missing locale file: config/locales/es_panic.yml")
    ensure
      path.write(backup) unless path.file?
    end
  end
end
