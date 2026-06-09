# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Branch coverage gaps (phases 4–5 batch)" do
  include BillingModelHelpers

  describe "ProjectLayer::SetPrimary validation branches [REQ-FIT-DXF-002]" do
    it "rejects unpersisted layers" do
      layer = ProjectLayer.new(layer_name: "CUT", included: true)

      expect { ProjectLayer::SetPrimary.call(layer) }
        .to raise_error(ArgumentError, /must be persisted/)
    end

    it "rejects layers without an attachment id" do
      project = create_project_for_spec!(title: "Set primary", bind_workspace: false)
      layer = project.project_layers.create!(layer_name: "CUT", included: true)

      expect { ProjectLayer::SetPrimary.call(layer) }
        .to raise_error(ArgumentError, /attachment required/)
    end

    it "clears sibling primary layers on the same attachment" do
      project = create_project_for_spec!(title: "Sibling primary", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "panel.dxf",
        content_type: "application/dxf"
      )
      attachment = project.input_dxf_attachments.first!
      Dxf::LayerSyncPerFile.call(project)
      first = project.project_layers.find_by!(layer_name: "PIECES", active_storage_attachment_id: attachment.id)
      second = project.project_layers.create!(
        layer_name: "ALT",
        active_storage_attachment_id: attachment.id,
        included: true
      )
      ProjectLayer::SetPrimary.call(first)
      first.update!(layer_role: :primary)

      ProjectLayer::SetPrimary.call(second)

      expect(first.reload.layer_role).to be_nil
      expect(second.reload.layer_role).to eq("primary")
      expect(second.included?).to be(true)
    end
  end

  describe "Nesting::MotherPieceStillPresent [REQ-FIT-SPLIT-001]" do
    let(:project) { create_project_for_spec!(title: "Mother present", bind_workspace: false) }
    let(:rings) { [ [ [ 0.0, 0.0 ], [ 100.0, 0.0 ], [ 100.0, 50.0 ], [ 0.0, 50.0 ] ] ] }

    it "returns false when the project has no DXF attachments" do
      expect(
        Nesting::MotherPieceStillPresent.call(project: project, mother_rings: rings, layer_name: "PIECES")
      ).to be(false)
    end

    it "returns false when mother geometry no longer matches extracted pieces" do
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      shifted = [ [ [ 999.0, 999.0 ], [ 1099.0, 999.0 ], [ 1099.0, 1049.0 ], [ 999.0, 1049.0 ] ] ]

      expect(
        Nesting::MotherPieceStillPresent.call(project: project, mother_rings: shifted, layer_name: "PIECES")
      ).to be(false)
    end

    it "returns true when matching geometry is still extractable" do
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(
        io: File.open(sample_dxf),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      allow(Dxf::PieceRingsLister).to receive(:list).and_return([ rings ])

      expect(
        Nesting::MotherPieceStillPresent.call(project: project, mother_rings: rings, layer_name: "PIECES")
      ).to be(true)
    end
  end

  describe "ProjectsController private branches [REQ-FIT-UI-001]" do
    subject(:controller) { ProjectsController.new }

    let(:project) { create_project_for_spec!(title: "Projects branch", bind_workspace: false) }

    before do
      controller.request = ActionDispatch::TestRequest.create
      controller.response = ActionDispatch::TestResponse.new
      allow(controller).to receive(:session).and_return({})
      allow(controller).to receive(:current_user).and_return(nil)
    end

    it "redirects index to start" do
      expect(controller).to receive(:redirect_to).with("/empezar")
      controller.index
    end

    it "skips workshop UX assignment when no project is bound" do
      controller.instance_variable_set(:@project, nil)

      controller.send(:assign_workshop_ux)

      expect(controller.instance_variable_get(:@workshop_ux)).to be_nil
    end

    it "no-ops sheet quantity normalization when attributes are blank" do
      expect { controller.send(:normalize_sheet_quantities!, nil) }.not_to raise_error
      expect { controller.send(:normalize_sheet_quantities!, {}) }.not_to raise_error
    end

    it "no-ops sheet inventory sync when attributes are blank" do
      expect(SheetStocks::SyncInventory).not_to receive(:call)

      controller.send(:sync_sheet_inventory!, project, nil)
      controller.send(:sync_sheet_inventory!, project, {})
    end

    it "builds nesting sync streams with preview zone when not processing" do
      project.update!(status: :completed)
      controller.instance_variable_set(:@project, project)
      controller.instance_variable_set(:@nesting_preview, Nesting::PreviewPresenter.for(project))
      controller.instance_variable_set(:@nesting_orphans, Nesting::OrphansPresenter.for(project))
      allow(controller).to receive(:workshop_ux).and_return(instance_double(Workshop::UxMode, show_preview_zone?: true))
      allow(controller).to receive(:current_user).and_return(nil)
      allow(Billing::PlanDownloadAvailability).to receive(:plan_included?).and_return(false)

      streams = controller.send(:nesting_sync_streams)

      expect(streams.size).to eq(4)
    end

    it "omits preview zone streams while processing" do
      project.update!(status: :processing, progress_percent: 10, progress_message: "nesting.phase.fill")
      controller.instance_variable_set(:@project, project)
      allow(controller).to receive(:workshop_ux).and_return(instance_double(Workshop::UxMode, show_preview_zone?: true))

      streams = controller.send(:nesting_sync_streams)

      expect(streams.size).to eq(2)
    end
  end

  describe "Workspace::TabLeave nil-safe request telemetry [REQ-FIT-AUTH-001]" do
    it "expires projects without request context" do
      project = Project.create!(ephemeral: true, title: "Tab leave nil request", status: :draft)
      session = { anonymous_session_key: "anon-tab-leave" }
      Workspace.bind!(session, project, tab_id: Workspace::DEFAULT_TAB_ID)
      allow(Analytics::TrackEvent).to receive(:call)
      allow(Analytics::ResolveCountry).to receive(:call).and_return(nil)

      Workspace.expire_project_everywhere!(session, project, request: nil)

      expect(Project.exists?(project.id)).to be(false)
      expect(Analytics::TrackEvent).to have_received(:call).with(
        "project_discarded",
        hash_including(user_id: nil, ip: nil, user_agent: nil)
      )
    end

    it "no-ops tab leave when the tab is not bound" do
      session = {}

      expect do
        Workspace.expire_tab_after_closure!(session, tab_id: "missing-tab", request: nil)
      end.not_to change(Project, :count)
    end
  end
end
