# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Orphan auto split", type: :system do
  include ActionView::RecordIdentifier

  around do |example|
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
    example.run
    ActiveJob::Base.queue_adapter = previous_adapter
  end

  let(:preview_payload) do
    {
      "piece_key" => "0",
      "feasible" => true,
      "reason" => nil,
      "children" => [
        {
          "label" => "a",
          "rings" => [ [ [ 0.0, 0.0 ], [ 100.0, 0.0 ], [ 100.0, 50.0 ], [ 0.0, 50.0 ] ] ]
        },
        {
          "label" => "b",
          "rings" => [ [ [ 100.0, 0.0 ], [ 200.0, 0.0 ], [ 200.0, 50.0 ], [ 100.0, 50.0 ] ] ]
        }
      ],
      "cut_segments" => [
        [ [ 100.0, 0.0 ], [ 100.0, 50.0 ] ]
      ]
    }
  end

  before do
    allow(Nesting::SplitPlannerRunner).to receive(:call).and_return(preview_payload)
  end

  def workspace_project_from_session
    session = page.driver.request.session
    Project.find(session[Workspace::SESSION_KEY])
  end

  def attach_oversized_piece!(project)
    dxf_path = Rails.root.join("tmp/oversized_orphan_e2e.dxf")
    python = Rails.root.join("nesting_engine/.venv/bin/python")
    script = <<~PY
      import ezdxf
      doc = ezdxf.new("R2010")
      doc.modelspace().add_lwpolyline(
          [(0, 0), (500, 0), (500, 500), (0, 500)],
          close=True,
          dxfattribs={"layer": "PIECES"},
      )
      doc.saveas(#{dxf_path.to_s.inspect})
    PY
    system(python.to_s, "-c", script, exception: true)

    project.input_dxf.attach(
      io: File.open(dxf_path),
      filename: "oversized.dxf",
      content_type: "application/dxf"
    )
    project.project_layers.create!(layer_name: "PIECES", included: true)
    project.sheet_stocks.destroy_all
    project.sheet_stocks.create!(width_mm: 100, height_mm: 100, quantity: 1, sort_order: 0)
    project.update!(kerf_mm: 0, margin_mm: 0, status: :ready)
  end

  it "[REQ-FIT-SPLIT-001] [REQ-FIT-UI-002] shows split preview after choosing Dividir con Fitloop" do
    visit start_project_path
    project = workspace_project_from_session
    attach_oversized_piece!(project)

    nesting_run = project.nesting_runs.create!(status: "processing", params_snapshot: {})
    NestingJob.perform_now(nesting_run.id)
    project.reload

    expect(project.status).to eq("partial")

    visit project_path(project)

    expect(page).to have_css('[data-testid="nesting-orphans"]')
    expect(page).to have_css('[data-testid="orphan-card"]', count: 1)

    within('[data-testid="orphan-card"]') do
      click_button I18n.t("nesting.split.choose_system")
    end

    expect(page).to have_css('[data-testid="split-plan-preview"]', wait: 5)

    click_button I18n.t("nesting.split.accept")

    project.reload
    expect(project.derived_pieces.count).to eq(2)
    expect(OrphanResolution.find_by!(project: project, piece_key: "0").resolution_state).to eq("resolved")
    expect(page).to have_css('[data-testid="orphan-split-applied"]')
    expect(page).to have_css('[data-testid="nest-updated-pieces"]')
  end
end
