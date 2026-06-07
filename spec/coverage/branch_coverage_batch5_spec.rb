# frozen_string_literal: true

require "rails_helper"

# Batch 5: remaining SimpleCov branch gaps (35 paths from analyze_coverage.rb).
RSpec.describe "Branch coverage batch 5" do
  include BillingModelHelpers
  include Rails.application.routes.url_helpers

  describe Billing::RetainNestedDxf, "[REQ-FIT-BILL-003]" do
    it "skips attach when retained_nested_dxf is already present" do
      user = create_billing_user!
      run = create_nesting_run!
      grant = DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: nil
      )
      grant.retained_nested_dxf.attach(
        io: StringIO.new("existing"),
        filename: "existing.dxf",
        content_type: "application/dxf"
      )
      run.project.nested_dxf.attach(
        io: StringIO.new("project-nested"),
        filename: "project.dxf",
        content_type: "application/dxf"
      )

      described_class.call(grant: grant, nesting_run: run)

      expect(grant.reload.retained_nested_dxf.download).to eq("existing")
    end

    it "raises when project nested_dxf is missing" do
      user = create_billing_user!
      run = create_nesting_run!
      grant = DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: nil
      )

      expect do
        described_class.call(grant: grant, nesting_run: run)
      end.to raise_error(ArgumentError, /nested_dxf missing/)
    end
  end

  describe NestingJob, type: :job do
    it "treats sheets without pieces as zero placed count" do
      project = create_project_for_spec!(title: "Pieces nil", bind_workspace: false)
      nesting_run = project.nesting_runs.create!(status: "processing")
      output_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s, "output")
      FileUtils.mkdir_p(output_dir)
      File.write(output_dir.join("placements.json"), { "sheets" => [ { "label" => "empty" } ] }.to_json)
      job = described_class.new

      expect(job.send(:parse_pieces_count, nesting_run)).to eq(0)
    ensure
      FileUtils.rm_rf(Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s))
    end
  end

  describe Billing::Money, "[REQ-FIT-BILL-001]" do
    it "uses Currency objects directly in from_major" do
      currency = Billing::Currency.parse(:crc)

      money = described_class.from_major(BigDecimal("10.5"), currency)

      expect(money.currency).to eq(currency)
      expect(money.amount).to eq(BigDecimal("10.5"))
    end
  end

  describe Nesting::SheetStockRow, "[REQ-FIT-NEST-004]" do
    it "rejects negative finite quantities" do
      expect do
        described_class.new(width_mm: 500, height_mm: 800, quantity: -1, sort_order: 0)
      end.to raise_error(ArgumentError, /quantity must be nil or at least 1/)
    end
  end

  describe Admin::HaciendaSummaryRows, "[REQ-FIT-ADMIN-001]" do
    it "prefers total_amount when it is positive" do
      payment = Payment.new(amount: 10.0, total_amount: 42.0)

      expect(described_class.net_collected(payment)).to eq(42.0)
    end
  end

  describe Nesting::LocalizedProgressMessage, "[REQ-FIT-JOB-001]" do
    it "returns empty text for blank progress on in-progress projects" do
      project = create_project_for_spec!(title: "In progress blank", bind_workspace: false)
      project.update!(status: :processing, progress_message: "")

      expect(described_class.for(project)).to eq("")
    end
  end

  describe Nesting::ProgressSnapshot, "[REQ-FIT-JOB-001]" do
    it "keeps explicit message_key values from progress payloads" do
      snapshot = described_class.from_hash(
        {
          "version" => 1,
          "phase_id" => "fill",
          "percent" => 12,
          "message_key" => "nesting.phase.queued"
        },
        last_percent: 0
      )

      expect(snapshot.message_key).to eq("nesting.phase.queued")
    end
  end

  describe PersistWorkspaceSheetInventoryDraft, "[REQ-FIT-UI-005]" do
    it "stashes composer draft after a successful save" do
      project = Project.create!(ephemeral: true, title: "Composer draft ok", status: :draft)
      session = { Workspace::SESSION_KEY => project.id }
      params = ActionController::Parameters.new(
        project: {
          sheet_stocks_attributes: {
            "0" => {
              width_mm: 1200,
              height_mm: 2400,
              quantity: "2",
              sort_order: 0,
              _destroy: "0"
            }
          }
        },
        composer_draft: { width_mm: "1200", height_mm: "2400", quantity: "2" }
      )

      expect(described_class.call(session: session, params: params)).to be(true)
      expect(session[described_class::COMPOSER_SESSION_KEY]).to include("width_mm" => "1200")
    end
  end

  describe Nesting::FailRun, "[REQ-FIT-JOB-001]" do
    it "returns false when the nesting run has no project" do
      run = create_nesting_run!
      allow(run).to receive(:project).and_return(nil)

      expect(described_class.call(nesting_run: run)).to be(false)
    end
  end

  describe Nesting::ProgressEta, "[REQ-FIT-JOB-001]" do
    it "returns the deadline when only pieces_total is known" do
      started = 3.minutes.ago

      eta = described_class.estimate(
        started_at: started,
        time_limit_sec: 120,
        pieces_total: 8,
        pieces_placed: 0
      )

      expect(eta).to be_within(1.second).of(started + 120.seconds)
    end
  end

  describe ProjectLayer::SetPrimary, "[REQ-FIT-DXF-002]" do
    it "raises when clearing sibling primaries exceeds the bound" do
      stub_const("ProjectLayer::SetPrimary::MAX_SIBLING_CLEAR", 0)
      project = create_project_for_spec!(title: "Sibling bound", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      attachment_id = project.input_dxf_attachments.first!.id
      first = project.project_layers.first!
      first.update!(layer_role: :primary, included: true)
      second = project.project_layers.create!(
        layer_name: "SECOND_PRIMARY",
        active_storage_attachment_id: attachment_id,
        included: false
      )

      expect { described_class.call(second) }.to raise_error(/sibling clear bound exceeded/)
      expect(first.reload.layer_role).to eq("primary")
    end
  end

  describe Billing::Onvo::CardInput, "[REQ-FIT-BILL-001]" do
    it "rejects non-sandbox PANs in ONVO test mode" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ONVO_MODE", "test").and_return("test")

      expect do
        described_class.parse!(
          holder_name: "Test User",
          card_number: "424242424242424242",
          card_exp: "12/30",
          cvv: "123"
        )
      end.to raise_error(ArgumentError, /card_number_test_only/)
    end
  end

  describe Billing::Onvo::ConfirmSinpePayment, "[REQ-FIT-BILL-001]" do
    it "requires a payment object" do
      expect do
        described_class.call(payment: nil, identification: "123456789", mobile_number: "88888888")
      end.to raise_error(ArgumentError, /payment required/)
    end

    it "confirms a fresh SINPE transfer through ONVO" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download",
        onvo_payment_intent_id: "pi_sinpe_fresh"
      )
      client = instance_double(Billing::Onvo::Client)
      allow(client).to receive(:create_payment_method).and_return({ id: "pm_fresh" })
      allow(client).to receive(:confirm_payment_intent).and_return({ status: "processing" })

      payload = described_class.call(
        payment: payment,
        identification: "123456789",
        mobile_number: "88888888",
        client: client
      )

      expect(payload.fetch(:status)).to eq("processing")
      expect(client).to have_received(:create_payment_method)
    end
  end

  describe Billing::Onvo::HandleWebhookEvent, "[REQ-FIT-BILL-001]" do
    it "abandons webhooks for payments already marked abandoned" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "card_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        onvo_payment_intent_id: "pi_already_abandoned",
        onvo_mode: "test",
        gateway_provider: "onvo",
        gateway_status: "requires_action",
        checkout_abandoned_at: 1.minute.ago
      )

      result = described_class.call(
        payload: {
          type: "payment-intent.failed",
          data: { id: payment.onvo_payment_intent_id, status: "failed" }
        }
      )

      expect(result).to eq(:abandoned)
    end
  end

  describe Nesting::ConfigBuilder, "[REQ-FIT-CLI-001]" do
    it "omits auxiliary_layers when a primary has no auxiliary siblings" do
      project = create_project_for_spec!(title: "Primary only", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      layer = project.project_layers.first!
      layer.update!(included: true, layer_role: :primary)
      work_dir = Rails.root.join("tmp/nesting_runs", "batch5-config")
      FileUtils.mkdir_p(work_dir)
      input = work_dir.join("input", "piece.dxf")
      FileUtils.mkdir_p(input.dirname)
      FileUtils.cp(sample_dxf, input)

      payload = described_class.build(project: project, work_dir: work_dir, input_paths: [ input ])
      file_entry = payload.fetch(:input_files).first

      expect(file_entry).to include(:primary_layer)
      expect(file_entry).not_to have_key(:auxiliary_layers)
    ensure
      FileUtils.rm_rf(work_dir)
    end
  end

  describe Nesting::JobRunner, "[REQ-FIT-JOB-001]" do
    it "returns immediately when cancel was requested before the CLI runs" do
      run = create_nesting_run!
      run.update!(status: "processing", cancel_requested_at: Time.current)
      allow(Nesting::CliRunner).to receive(:call)

      expect(described_class.call(nesting_run: run)).to be_nil
      expect(Nesting::CliRunner).not_to have_received(:call)
    end

    it "returns after a successful CLI when cancel is observed at the end" do
      stub_const("Nesting::JobRunner::CANCEL_CACHE_TTL_SEC", 0)
      project = create_project_for_spec!(title: "Late cancel", bind_workspace: false)
      run = project.nesting_runs.create!(status: "processing")
      allow(Nesting::CliRunner).to receive(:call) { run.update!(cancel_requested_at: Time.current) }
      allow(Nesting::ApplyCancel).to receive(:call)

      described_class.call(nesting_run: run)

      expect(Nesting::ApplyCancel).to have_received(:call).with(hash_including(nesting_run: run))
    end

    it "raises CancelledError when cancel is requested during runner initialization inside timeout" do
      project = create_project_for_spec!(title: "Cancel inside timeout", bind_workspace: false)
      run = project.nesting_runs.create!(status: "processing")

      allow_any_instance_of(described_class).to receive(:cancel_requested?).and_return(false, true)
      allow(Nesting::ApplyCancel).to receive(:call)

      described_class.call(nesting_run: run)

      expect(Nesting::ApplyCancel).to have_received(:call).with(hash_including(nesting_run: run))
    end
  end

  describe Nesting::OrphansPresenter::Orphan, "[REQ-FIT-SPLIT-001]" do
    it "treats a nil split proposal as not failed and not feasible" do
      orphan = described_class.new(split_proposal: nil)

      expect(orphan.split_plan_failed?).to be_nil
      expect(orphan.split_not_feasible?).to be_nil
      expect(orphan.split_accepted?).to be_nil
      expect(orphan.split_applied?).to be(false)
    end
  end

  describe Nesting::ProjectStatusSync, "[REQ-FIT-JOB-001]" do
    it "does not treat nil report_json as cancelled" do
      project = create_project_for_spec!(title: "Nil report", bind_workspace: false)
      run = project.nesting_runs.create!(status: "failed")
      allow(run).to receive(:report_json).and_return(nil)
      sync = described_class.new(project: project)

      expect(sync.send(:cancelled_run?, run)).to be(false)
    end
  end

  describe Users::RegistrationsController, "[REQ-FIT-AUTH-002]" do
    it "skips unconfirmed_email capture when the resource does not support it" do
      user = create_billing_user!
      adapter = double("UserAdapter", get!: user)
      host = described_class.new
      host.request = ActionDispatch::TestRequest.create
      host.response = ActionDispatch::TestResponse.new
      allow(host).to receive(:current_user).and_return(user)
      allow(host).to receive(:resource_class).and_return(User)
      allow(host).to receive(:resource_name).and_return(:user)
      allow(User).to receive(:to_adapter).and_return(adapter)
      allow(host).to receive(:account_update_params).and_return(ActionController::Parameters.new(user: {}))
      allow(host).to receive(:sign_in_after_change_password?).and_return(false)
      allow(host).to receive(:respond_with)
      allow(host).to receive(:set_flash_message_for_update)
      allow(host).to receive(:after_update_path_for).and_return("/cuenta")
      allow(user).to receive(:respond_to?) do |name, *rest|
        name == :unconfirmed_email ? false : user.class.instance_method(:respond_to?).bind(user).call(name, *rest)
      end
      allow(host).to receive(:update_resource).and_return(true)

      host.update

      expect(host).to have_received(:update_resource)
    end
  end

  describe Users::SessionsController, "[REQ-FIT-AUTH-002]", type: :request do
    it "skips logout analytics when destroy is called while signed out" do
      user = create_billing_user!
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

      allow(Analytics::TrackEvent).to receive(:call)
      allow_any_instance_of(Users::SessionsController).to receive(:user_signed_in?).and_return(false)

      delete destroy_user_session_path

      expect(Analytics::TrackEvent).not_to have_received(:call).with("user_logged_out", anything)
    end
  end

  describe OrphanResolutionsController, "[REQ-FIT-SPLIT-001]" do
    it "returns early when checkout lock blocks workshop mutations" do
      project = create_project_for_spec!(title: "Orphan lock", bind_workspace: false)
      host = described_class.new
      host.instance_variable_set(:@project, project)
      allow(host).to receive(:reject_workshop_mutation_if_pending_payment!).and_return(true)
      allow(host).to receive(:redirect_to)

      expect(Nesting::SplitPlanJob).not_to receive(:perform_later)

      host.update
    end
  end

  describe SplitProposalsController, "[REQ-FIT-SPLIT-001]" do
    it "returns early when checkout lock blocks regeneration" do
      project = create_project_for_spec!(title: "Split lock", bind_workspace: false)
      resolution = project.orphan_resolutions.create!(
        piece_key: "0",
        reason: "oversized_for_sheet",
        resolution_state: :system_split
      )
      host = described_class.new
      host.instance_variable_set(:@project, project)
      host.instance_variable_set(:@orphan_resolution, resolution)
      allow(host).to receive(:reject_workshop_mutation_if_pending_payment!).and_return(true)
      allow(host).to receive(:redirect_to)

      expect(Nesting::SplitPlanJob).not_to receive(:perform_later)

      host.regenerate
    end
  end

  describe ProjectLayersController, "[REQ-FIT-DXF-001]" do
    it "returns early when checkout lock blocks layer updates" do
      project = create_project_for_spec!(title: "Layers lock", bind_workspace: false)
      host = described_class.new
      host.instance_variable_set(:@project, project)
      allow(host).to receive(:reject_workshop_mutation_if_pending_payment!).and_return(true)
      allow(host).to receive(:redirect_to)

      expect(ProjectLayerSelection).not_to receive(:apply!)

      host.update
    end
  end

  describe Dxf::LayerSyncPerFile, "[REQ-FIT-DXF-001]" do
    it "no-ops tempfile cleanup when Tempfile creation fails" do
      project = create_project_for_spec!(title: "Tempfile fail", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      attachment = project.input_dxf_attachments.first!
      sync = described_class.new(project)
      allow(Tempfile).to receive(:new).and_raise(StandardError, "disk full")

      expect { sync.send(:with_downloaded_path, attachment) { :unused } }
        .to raise_error(StandardError, "disk full")
    end
  end

  describe MisPagosController, "[REQ-FIT-BILL-002]" do
    it "returns nil when auto_download does not match a grant" do
      user = create_billing_user!
      host = described_class.new
      allow(host).to receive(:params).and_return(ActionController::Parameters.new(auto_download: "999999"))
      allow(host).to receive(:current_user).and_return(user)

      expect(host.send(:auto_download_grant)).to be_nil
    end

    it "returns nil when the matched grant is not retention-active" do
      user = create_billing_user!
      run = create_nesting_run!
      grant = DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: 1.day.ago
      )
      host = described_class.new
      allow(host).to receive(:params).and_return(ActionController::Parameters.new(auto_download: grant.id.to_s))
      allow(host).to receive(:current_user).and_return(user)

      expect(host.send(:auto_download_grant)).to be_nil
    end
  end

  describe Nesting::MotherPieceStillPresent, "[REQ-FIT-SPLIT-001]" do
    it "returns false when rings cannot be keyed" do
      project = create_project_for_spec!(title: "No key", bind_workspace: false)

      expect(described_class.call(project: project, mother_rings: [], layer_name: "PIECES")).to be(false)
    end
  end

  describe DownloadPaywallController, "[REQ-FIT-BILL-001]" do
    it "stops set_workspace_project after redirecting for a missing tab id" do
      host = described_class.new
      host.request = ActionDispatch::TestRequest.create
      host.response = ActionDispatch::TestResponse.new
      allow(host).to receive(:expire_workspace_after_tab_closure!).and_return(false)
      allow(host).to receive(:missing_tab_id_for_bound_workspaces?).and_return(true)
      allow(host).to receive(:redirect_to)

      host.send(:set_workspace_project)

      expect(host).to have_received(:redirect_to).with(
        start_project_path,
        alert: I18n.t("workspace.expired")
      )
    end

    it "handles nil project in show analytics tracking" do
      host = described_class.new
      host.request = ActionDispatch::TestRequest.create
      host.response = ActionDispatch::TestResponse.new
      host.instance_variable_set(:@project, nil)
      allow(host).to receive(:current_user).and_return(nil)
      allow(host).to receive(:session).and_return({})
      allow(Billing::GeoPaymentDefaults).to receive(:from_request).and_return(available_payment_methods: [])
      allow(Billing::PaymentSelection).to receive(:resolve).and_return(nil)
      allow(Billing::PlanDownloadAvailability).to receive(:plan_included?).and_return(false)
      allow(Billing::PlanDownloadAvailability).to receive(:single_download_checkout_allowed?).and_return(false)
      allow(Analytics::TrackEvent).to receive(:call)

      host.show

      expect(Analytics::TrackEvent).to have_received(:call).with(
        "paywall_viewed",
        hash_including(project_id: nil)
      )
    end
  end

  describe DownloadPaywallController, "[REQ-FIT-BILL-001]", type: :request do
    it "records nil user_id for guest paywall views" do
      allow(Analytics::TrackEvent).to receive(:call)

      get download_paywall_workshop_path

      expect(Analytics::TrackEvent).to have_received(:call).with(
        "paywall_viewed",
        hash_including(user_id: nil)
      )
    end

    it "skips guest return-to storage for signed-in users" do
      user = create_billing_user!
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
      get start_project_path
      follow_redirect!

      get download_paywall_workshop_path

      expect(session[:workspace_return_to]).to be_nil
    end
  end

  describe "MisPagos::DownloadsController", "[REQ-FIT-BILL-003]", type: :request do
    it "records nil project_id when the grant has no nesting run" do
      user = create_billing_user!
      grant = DownloadGrant.create!(
        user: user,
        nesting_run: nil,
        kind: "single_purchase",
        retained_until: 1.day.from_now
      )
      grant.retained_nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
      allow(Analytics::TrackEvent).to receive(:call)
      allow(Billing::RetainedDownload).to receive(:serve!).and_return(
        data: "nested",
        filename: "nested.dxf",
        content_type: "application/dxf"
      )

      get mis_pagos_download_path(id: grant.id)

      expect(Analytics::TrackEvent).to have_received(:call).with(
        "download_completed",
        hash_including(project_id: nil, nesting_run_id: nil)
      )
    end
  end
end
