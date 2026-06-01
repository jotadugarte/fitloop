# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::FunnelStages, "[REQ-FIT-ANALYTICS-001]" do
  it "defines the ordered funnel stages for admin analytics" do
    expect(described_class::ORDERED).to eq(
      %w[
        workspace_started
        first_dxf_uploaded
        nest_completed
        paywall_viewed
        payment_succeeded
        download_completed
      ]
    )
  end

  it "lists only catalog-registered event types" do
    described_class::ORDERED.each do |stage|
      expect(Analytics::EventCatalog.all_event_types).to include(stage)
    end
  end
end
