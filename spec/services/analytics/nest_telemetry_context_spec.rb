# frozen_string_literal: true

require "rails_helper"

RSpec.describe Analytics::NestTelemetryContext, "[REQ-FIT-ANALYTICS-001]" do
  let(:project) { Project.create!(title: "Context bench", ephemeral: true) }
  let(:nesting_run) do
    project.nesting_runs.create!(
      status: "completed",
      created_at: 10.seconds.ago,
      started_at: 5.seconds.ago,
      finished_at: Time.current
    )
  end

  def seed_event!(event_type:, occurred_at:, **attrs)
    UserEvent.create!(
      {
        event_type: event_type,
        project_id: project.id,
        priority: "low",
        occurred_at: occurred_at
      }.merge(attrs)
    )
  end

  it "prefers the latest event at or before nest start" do
    seed_event!(
      event_type: "workspace_started",
      occurred_at: 8.seconds.ago,
      anonymous_session_key: "early-session",
      tab_id: "tab-early"
    )
    seed_event!(
      event_type: "first_dxf_uploaded",
      occurred_at: 6.seconds.ago,
      anonymous_session_key: "late-session",
      tab_id: "tab-late"
    )

    context = described_class.from(project: project, nesting_run: nesting_run)

    expect(context.anonymous_session_key).to eq("late-session")
    expect(context.tab_id).to eq("tab-late")
  end

  it "ignores events recorded after nest start on the primary lookup" do
    seed_event!(
      event_type: "workspace_started",
      occurred_at: 8.seconds.ago,
      anonymous_session_key: "good-session",
      tab_id: "tab-good"
    )
    seed_event!(
      event_type: "paywall_viewed",
      occurred_at: 3.seconds.ago,
      anonymous_session_key: "bad-session",
      tab_id: "tab-bad"
    )

    context = described_class.from(project: project, nesting_run: nesting_run)

    expect(context.anonymous_session_key).to eq("good-session")
    expect(context.tab_id).to eq("tab-good")
  end

  it "falls back to finished_at when async workshop events land after nest start" do
    seed_event!(
      event_type: "workspace_started",
      occurred_at: 2.seconds.ago,
      anonymous_session_key: "async-session",
      tab_id: "tab-async"
    )

    context = described_class.from(project: project, nesting_run: nesting_run)

    expect(context.anonymous_session_key).to eq("async-session")
  end

  it "prefers delayed workshop events over post-start paywall on fallback" do
    seed_event!(
      event_type: "paywall_viewed",
      occurred_at: 3.seconds.ago,
      anonymous_session_key: "paywall-session",
      tab_id: "tab-paywall"
    )
    seed_event!(
      event_type: "workspace_started",
      occurred_at: 2.seconds.ago,
      anonymous_session_key: "async-session",
      tab_id: "tab-async"
    )

    context = described_class.from(project: project, nesting_run: nesting_run)

    expect(context.anonymous_session_key).to eq("async-session")
    expect(context.tab_id).to eq("tab-async")
  end
end
