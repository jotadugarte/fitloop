# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::Thresholds, "[REQ-FIT-ANALYTICS-001]" do
  let(:config_path) { Rails.root.join("config/analytics.yml") }

  describe "YAML loading and attributes" do
    it "exposes loaded threshold limits" do
      expect(described_class.funnel_conversion_min_percent).to eq(15)
      expect(described_class.payment_failure_rate_max_percent).to eq(20)
      expect(described_class.nest_duration_p95_max_seconds).to eq(600)
      expect(described_class.low_priority_events_per_hour).to eq(300)
    end
  end

  describe "breach checks" do
    it "detects funnel conversion rate breach" do
      # Breach if conversion percent is lower than min
      expect(described_class.funnel_breached?(10)).to be(true)
      expect(described_class.funnel_breached?(15)).to be(false)
      expect(described_class.funnel_breached?(20)).to be(false)
    end

    it "detects payment failure rate breach" do
      # Breach if failure percent is greater than max
      expect(described_class.payment_failure_breached?(25)).to be(true)
      expect(described_class.payment_failure_breached?(20)).to be(false)
      expect(described_class.payment_failure_breached?(10)).to be(false)
    end

    it "detects nest duration breach" do
      # Breach if p95 duration is greater than max
      expect(described_class.nest_duration_breached?(650)).to be(true)
      expect(described_class.nest_duration_breached?(600)).to be(false)
      expect(described_class.nest_duration_breached?(500)).to be(false)
    end
  end

  describe "hot reload on mtime" do
    before do
      # Ensure file exists and cache is clear/memoized
      described_class.funnel_conversion_min_percent
    end

    it "hot-reloads configuration when the config file is updated" do
      original_value = described_class.funnel_conversion_min_percent

      # Simulate hot reload by modifying the file or changing its mtime
      # We can mock the mtime and file content, or write to it
      original_content = File.read(config_path)
      begin
        new_content = original_content.gsub("funnel_conversion_min_percent: 15", "funnel_conversion_min_percent: 10")
        File.write(config_path, new_content)
        # Update the mtime to be in the future to trigger reload
        FileUtils.touch(config_path, mtime: (Time.current + 5.seconds).to_time)

        expect(described_class.funnel_conversion_min_percent).to eq(10)
      ensure
        # Restore original content and touch again
        File.write(config_path, original_content)
        FileUtils.touch(config_path)
      end
    end
  end
end
