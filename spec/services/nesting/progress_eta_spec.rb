# frozen_string_literal: true

require "rails_helper"

RSpec.describe Nesting::ProgressEta, "[REQ-FIT-JOB-001]" do
  it "returns the deadline when only pieces_total is positive [REQ-FIT-JOB-001]" do
    started = 2.minutes.ago

    eta = described_class.estimate(
      started_at: started,
      time_limit_sec: 90,
      pieces_total: 12,
      pieces_placed: 0
    )

    expect(eta).to be_within(1.second).of(started + 90.seconds)
  end

  it "returns the deadline when elapsed time is zero [REQ-FIT-JOB-001]" do
    started = Time.zone.parse("2026-06-06 12:00:00")

    eta = described_class.estimate(
      started_at: started,
      time_limit_sec: 120,
      pieces_total: 10,
      pieces_placed: 5,
      now: started
    )

    expect(eta).to eq(started + 120.seconds)
  end
end
