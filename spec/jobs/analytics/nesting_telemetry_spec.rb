# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Nesting job telemetry", "[REQ-FIT-ANALYTICS-001]", type: :job do
  let(:project) do
    Project.create!(
      title: "Telemetry test bench",
      ephemeral: true,
      sheet_stocks_attributes: {
        "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
      }
    )
  end
  let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }
  let(:nesting_run) { project.nesting_runs.create!(status: "processing", started_at: Time.current - 5.seconds) }

  let(:user) { create_billing_user!(email: "telemetry@example.com") }

  before do
    project.input_dxf.attach(
      io: File.open(sample_dxf),
      filename: "piece.dxf",
      content_type: "application/dxf"
    )
    project.project_layers.create!(layer_name: "PIECES", included: true)

    # Seed a workspace_started event to verify metadata extraction
    UserEvent.create!(
      event_type: "workspace_started",
      project_id: project.id,
      anonymous_session_key: "anon-1234",
      user_id: user.id,
      tab_id: "tab-abc",
      ip: "127.0.0.1",
      user_agent: "TestAgent",
      country_code: "CR",
      locale: "es",
      priority: "low",
      occurred_at: Time.current
    )
  end

  it "tracks nest_completed event with duration, counts, status, and orphans by reason on job finish" do
    expect {
      NestingJob.perform_now(nesting_run.id)
    }.to change(UserEvent.where(event_type: "nest_completed"), :count).by(1)

    event = UserEvent.where(event_type: "nest_completed").last
    expect(event.priority).to eq("critical")
    expect(event.user_id).to eq(user.id)
    expect(event.anonymous_session_key).to eq("anon-1234")
    expect(event.tab_id).to eq("tab-abc")
    expect(event.ip).to eq("127.0.0.1")
    expect(event.user_agent).to eq("TestAgent")
    expect(event.country_code).to eq("CR")
    expect(event.locale).to eq("es")
    expect(event.nesting_run_id).to eq(nesting_run.id)
    expect(event.project_id).to eq(project.id)

    expect(event.properties["duration_ms"]).to be >= 0
    expect(event.properties["status"]).to eq("completed")
    expect(event.properties["sheets_used"]).to be_a(Integer)
    expect(event.properties["pieces_count"]).to be_a(Integer)
    expect(event.properties["orphans_by_reason"]).to be_a(Hash)
  end
end
