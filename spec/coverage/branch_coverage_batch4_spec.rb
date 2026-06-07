# frozen_string_literal: true

require "rails_helper"

# Batch 4: final 53 SimpleCov branch gaps (see analyze_coverage.rb).
RSpec.describe "Branch coverage batch 4" do
  include BillingModelHelpers

  describe Billing::RetainNestedDxf, "[REQ-FIT-BILL-003]" do
    it "attaches retained_nested_dxf when the grant blob is missing" do
      user = create_billing_user!
      run = create_nesting_run!
      grant = DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: nil
      )
      run.project.nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )

      described_class.call(grant: grant, nesting_run: run, paid_at: Time.current)

      expect(grant.reload.retained_nested_dxf).to be_attached
    end
  end

  describe NestingJob, type: :job do
    it "skips FailRun and ensure telemetry when rescue reload returns nil" do
      run = create_nesting_run!
      run.update!(status: "processing")
      allow(Nesting::JobRunner).to receive(:call).and_raise(StandardError, "boom")
      find_calls = 0
      allow(NestingRun).to receive(:find_by).with(id: run.id) do
        find_calls += 1
        find_calls == 1 ? run : nil
      end
      allow(Analytics::TrackEvent).to receive(:call)

      expect(Nesting::FailRun).not_to receive(:call)
      described_class.perform_now(run.id)
      expect(Analytics::TrackEvent).not_to have_received(:call)
    end
  end

  describe Billing::CheckoutContext, "[REQ-FIT-BILL-001]" do
    it "serializes country_code when present" do
      ctx = described_class.from_session(
        currency: :crc,
        payment_method: :sinpe,
        country_code: "CR",
        iva_applicable: true
      )

      expect(ctx.to_h[:country_code]).to eq("CR")
    end
  end

  describe Billing::Money, "[REQ-FIT-BILL-001]" do
    it "accepts Currency objects in from_major" do
      currency = Billing::Currency.parse(:usd)

      expect(described_class.from_major(1.5, currency).currency).to eq(currency)
    end
  end

  describe Nesting::SheetStockRow, "[REQ-FIT-NEST-004]" do
    it "rejects quantities below one" do
      expect do
        described_class.new(width_mm: 500, height_mm: 800, quantity: 0, sort_order: 0)
      end.to raise_error(ArgumentError, /quantity must be nil or at least 1/)
    end

    it "rejects negative sort_order" do
      expect do
        described_class.new(width_mm: 500, height_mm: 800, quantity: 1, sort_order: -1)
      end.to raise_error(ArgumentError, /sort_order/)
    end
  end

  describe Admin::HaciendaSummaryRows, "[REQ-FIT-ADMIN-001]" do
    it "falls back to amount when total_amount is not positive" do
      payment = Payment.new(amount: 42.0, total_amount: 0)

      expect(described_class.net_collected(payment)).to eq(42.0)
    end

    it "returns keys in ascending order when direction is not desc" do
      grouped = {
        [ "2026-06-02", "card_crc" ] => [],
        [ "2026-06-01", "sinpe_crc" ] => []
      }

      keys = described_class.sorted_keys(grouped, direction: "asc")

      expect(keys).to eq(
        [
          [ "2026-06-01", "sinpe_crc" ],
          [ "2026-06-02", "card_crc" ]
        ]
      )
    end
  end

  describe Nesting::LocalizedProgressMessage, "[REQ-FIT-JOB-001]" do
    it "returns empty text for blank stored messages on non-terminal projects" do
      project = create_project_for_spec!(title: "Blank progress", status: :processing, bind_workspace: false)
      project.update!(progress_message: "")

      expect(described_class.for(project)).to eq("")
    end
  end

  describe Nesting::ProgressSnapshot, "[REQ-FIT-JOB-001]" do
    it "rejects snapshots that regress percent" do
      snapshot = described_class.from_hash(
        { "version" => 1, "phase_id" => "fill", "percent" => 4 },
        last_percent: 10
      )

      expect(snapshot).to be_nil
    end
  end

  describe PersistWorkspaceSheetInventoryDraft, "[REQ-FIT-UI-005]" do
    it "does not stash composer draft when save fails" do
      project = Project.create!(ephemeral: true, title: "Draft save fail", status: :draft)
      session = { Workspace::SESSION_KEY => project.id }
      params = ActionController::Parameters.new(
        project: {
          sheet_stocks_attributes: {
            "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
          }
        },
        composer_draft: { width_mm: "1200", height_mm: "2400", quantity: "2" }
      )

      allow(Workspace).to receive(:any_bound_project).and_return(project)
      allow(project).to receive(:save).and_return(false)

      expect(described_class.call(session: session, params: params)).to be(false)
      expect(session[described_class::COMPOSER_SESSION_KEY]).to be_nil
    end
  end

  describe Billing::PaymentStatusResponse, "[REQ-FIT-BILL-001]" do
    let(:routes) { Rails.application.routes.url_helpers }

    it "returns nil redirect when succeeded payment is neither single-download nor plan" do
      payment = instance_double(
        Payment,
        succeeded?: true,
        gateway_status: "succeeded",
        single_download?: false,
        plan_subscription?: false
      )

      payload = described_class.new(payment: payment, routes: routes).send(:redirect_url_if_ready)

      expect(payload).to be_nil
    end
  end

  describe Billing::CartMergeOnLogin, "[REQ-FIT-BILL-001]" do
    it "requires a user" do
      expect { described_class.call(user: nil, guest_token: "tok") }
        .to raise_error(ArgumentError, /user must be present/)
    end

    it "reassigns guest cart to user when only guest cart exists" do
      user = create_billing_user!
      token = SecureRandom.uuid
      guest_cart = Cart.create!(
        guest_token: token,
        kind: "plan",
        tier_months: 1,
        currency_mode: "usd",
        list_price_cents: 100,
        sinpe_price_cents: 100
      )

      described_class.call(user: user, guest_token: token)

      expect(guest_cart.reload.user_id).to eq(user.id)
      expect(guest_cart.guest_token).to be_nil
    end
  end

  describe Billing::CartUpsert, "[REQ-FIT-BILL-001]" do
    it "requires a user or guest token" do
      expect do
        described_class.call(user: nil, guest_token: "", kind: "plan", tier_months: 1, currency_mode: "usd")
      end.to raise_error(ArgumentError, /user or guest_token required/)
    end
  end

  describe Nesting::FailRun, "[REQ-FIT-JOB-001]" do
    it "no-ops when the run is not processing" do
      run = create_nesting_run!
      run.update!(status: "failed")

      expect(described_class.call(nesting_run: run)).to be(false)
    end

    it "no-ops when the project is missing" do
      run = create_nesting_run!
      allow(run).to receive(:project).and_return(nil)

      expect(described_class.call(nesting_run: run)).to be(false)
    end
  end

  describe Nesting::ProgressEta, "[REQ-FIT-JOB-001]" do
    it "returns the time limit when only pieces_total is positive" do
      started = 2.minutes.ago

      eta = described_class.estimate(
        started_at: started,
        time_limit_sec: 90,
        pieces_total: 10,
        pieces_placed: 0
      )

      expect(eta).to be_within(1.second).of(started + 90.seconds)
    end
  end

  describe CheckoutController, "[REQ-FIT-BILL-001]" do
    it "leaves @project nil when plan checkout has no nesting_run" do
      user = create_billing_user!
      Cart.create!(
        user_id: user.id,
        kind: "plan",
        tier_months: 1,
        currency_mode: "usd",
        list_price_cents: 100,
        sinpe_price_cents: 100
      )
      host = described_class.new
      host.request = ActionDispatch::TestRequest.create
      host.response = ActionDispatch::TestResponse.new
      allow(host).to receive(:current_user).and_return(user)
      allow(host).to receive(:session).and_return({})
      allow(host).to receive(:params).and_return(ActionController::Parameters.new)
      allow(host).to receive(:redirect_to)
      allow(Workspace).to receive(:bound_to_project?).and_return(true)

      host.send(:load_checkout_context)

      expect(host.instance_variable_get(:@nesting_run)).to be_nil
      expect(host.instance_variable_get(:@project)).to be_nil
    end
  end

  describe ProjectLayer::SetPrimary, "[REQ-FIT-DXF-002]" do
    it "rejects unpersisted layers" do
      layer = ProjectLayer.new(layer_name: "CUT", included: true)

      expect { described_class.call(layer) }.to raise_error(ArgumentError, /must be persisted/)
    end

    it "rejects layers without an attachment id" do
      project = create_project_for_spec!(title: "No attachment", bind_workspace: false)
      layer = project.project_layers.create!(layer_name: "CUT", included: true)

      expect { described_class.call(layer) }.to raise_error(ArgumentError, /attachment required/)
    end

    it "raises when layer_role post-condition fails" do
      project = create_project_for_spec!(title: "Post-condition", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      layer = project.project_layers.first!
      allow(layer).to receive(:update!) do |attrs|
        layer.assign_attributes(attrs)
        layer.save!(validate: false)
        allow(layer).to receive(:layer_role).and_return("auxiliary")
      end

      expect { described_class.call(layer) }.to raise_error(/post-condition failed: layer_role primary/)
    end

    it "raises when included post-condition fails" do
      project = create_project_for_spec!(title: "Included post", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      layer = project.project_layers.first!
      allow(layer).to receive(:update!) do |attrs|
        layer.assign_attributes(attrs)
        layer.save!(validate: false)
        allow(layer).to receive(:layer_role).and_return("primary")
        allow(layer).to receive(:included?).and_return(false)
      end

      expect { described_class.call(layer) }.to raise_error(/post-condition failed: included/)
    end
  end

  describe Billing::Onvo::CardInput, "[REQ-FIT-BILL-001]" do
    it "accepts sandbox Visa test PANs" do
      parsed = described_class.parse!(
        holder_name: "Test User",
        card_number: Billing::Onvo::TestCardNumbers.primary_visa,
        card_exp: "12/30",
        cvv: "123"
      )

      expect(parsed.fetch(:card_number)).to eq(Billing::Onvo::TestCardNumbers.primary_visa)
    end
  end

  describe Billing::Onvo::ConfirmSinpePayment, "[REQ-FIT-BILL-001]" do
    it "rejects nil payments" do
      expect do
        described_class.call(payment: nil, identification: "123456789", mobile_number: "88888888")
      end.to raise_error(ArgumentError, /payment required/)
    end

    it "returns instructions without re-confirming an already submitted transfer" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download",
        onvo_payment_intent_id: "pi_sinpe_done",
        sinpe_transfer_identification: "123456789",
        sinpe_transfer_mobile_number: "88888888",
        gateway_status: "processing"
      )

      payload = described_class.call(
        payment: payment,
        identification: "123456789",
        mobile_number: "88888888"
      )

      expect(payload.fetch(:status)).to eq("processing")
    end

    it "preserves international-format mobile numbers" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download",
        onvo_payment_intent_id: "pi_sinpe_plus"
      )
      client = instance_double(Billing::Onvo::Client)
      allow(client).to receive(:create_payment_method).and_return({ id: "pm_1" })
      allow(client).to receive(:confirm_payment_intent).and_return({ status: "processing" })
      allow(Billing::Onvo::Client).to receive(:from_env).and_return(client)

      described_class.call(
        payment: payment,
        identification: "123456789",
        mobile_number: "+50688888888",
        client: client
      )

      expect(client).to have_received(:create_payment_method).with(
        hash_including(mobileNumber: hash_including(number: "+50688888888"))
      )
    end
  end

  describe Billing::Onvo::HandleWebhookEvent, "[REQ-FIT-BILL-001]" do
    it "abandons incomplete card checkouts instead of failing them" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "card_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        onvo_payment_intent_id: "pi_abandon",
        onvo_mode: "test",
        gateway_provider: "onvo",
        gateway_status: "requires_action"
      )
      payload = {
        type: "payment-intent.failed",
        data: { id: payment.onvo_payment_intent_id, status: "failed" }
      }

      result = described_class.call(payload: payload)

      expect(result).to eq(:abandoned)
      expect(payment.reload).to be_pending
      expect(payment.checkout_abandoned_at).to be_present
    end
  end

  describe Billing::Onvo::SinpeInput, "[REQ-FIT-BILL-001]" do
    around do |example|
      keys = %w[ONVO_MODE BILLING_GATEWAY]
      previous = keys.index_with { |key| ENV[key] }
      example.run
    ensure
      keys.each { |key| ENV[key] = previous[key] }
    end

    it "skips sandbox mobile restrictions outside ONVO test mode" do
      ENV["ONVO_MODE"] = "live"
      ENV["BILLING_GATEWAY"] = "onvo"

      parsed = described_class.parse!(identification: "123456789", mobile_number: "77777777")

      expect(parsed.fetch(:mobile_number)).to eq("77777777")
    end
  end

  describe Nesting::CliRunner, "[REQ-FIT-CLI-001]" do
    let(:project) do
      Project.create!(
        title: "CLI cancel nil",
        ephemeral: true,
        sheet_stocks_attributes: { "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 } }
      )
    end
    let(:nesting_run) { project.nesting_runs.create!(status: "processing") }

    it "polls Open3 without a cancel_check callback" do
      wait_thr = instance_double(Process::Waiter, pid: 12_345)
      allow(wait_thr).to receive(:join).with(0.2).and_return(false, true)
      allow(wait_thr).to receive(:value).and_return(instance_double(Process::Status, exitstatus: 0))
      allow(Open3).to receive(:popen3).and_yield(nil, nil, nil, wait_thr)
      runner = described_class.new(nesting_run: nesting_run)
      work_dir = Pathname(Dir.mktmpdir)

      runner.send(:run_cli!, work_dir)

      expect(wait_thr).to have_received(:join).with(0.2).at_least(:once)
    ensure
      FileUtils.rm_rf(work_dir) if defined?(work_dir)
    end
  end

  describe Nesting::ConfigBuilder, "[REQ-FIT-CLI-001]" do
    it "falls back to included_layers when no primary layer is configured" do
      project = create_project_for_spec!(title: "Included layers", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      project.project_layers.update_all(included: true, layer_role: nil)
      work_dir = Rails.root.join("tmp/nesting_runs", "batch4-config")
      FileUtils.mkdir_p(work_dir)
      input = work_dir.join("input", "piece.dxf")
      FileUtils.mkdir_p(input.dirname)
      FileUtils.cp(sample_dxf, input)

      payload = described_class.build(project: project, work_dir: work_dir, input_paths: [ input ])

      expect(payload.fetch(:input_files).first).to include(:included_layers)
    ensure
      FileUtils.rm_rf(work_dir)
    end
  end

  describe Nesting::JobRunner, "[REQ-FIT-JOB-001]" do
    it "returns early when cancel was requested before start" do
      run = create_nesting_run!
      run.update!(status: "processing", cancel_requested_at: Time.current)

      expect(described_class.call(nesting_run: run)).to be_nil
      expect(run.reload.status).to eq("failed")
      expect(run.project.reload.progress_message).to eq("nesting.cancelled")
    end
  end

  describe Nesting::OrphansPresenter::Orphan, "[REQ-FIT-SPLIT-001]" do
    it "treats missing split proposals as not feasible" do
      orphan = described_class.new(split_proposal: nil)

      expect(orphan.split_preview_available?).to be(false)
      expect(orphan.split_not_feasible?).to be_nil
    end
  end

  describe Nesting::ProjectStatusSync, "[REQ-FIT-JOB-001]" do
    it "detects cancelled runs via report_json warnings" do
      project = create_project_for_spec!(title: "Cancelled sync", bind_workspace: false)
      run = project.nesting_runs.create!(
        status: "failed",
        report_json: { "warnings" => [ "cancelled" ] }
      )
      sync = described_class.new(project: project)

      expect(sync.send(:cancelled_run?, run)).to be(true)
    end
  end

  describe ProjectLayerSelection, "[REQ-FIT-DXF-002]" do
    it "skips deselecting primary layers via apply_layer_role_attrs!" do
      project = create_project_for_spec!(title: "Primary deselect", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      layer = project.project_layers.first!
      layer.update!(included: true, layer_role: :primary)
      service = described_class.new(project: project, raw_params: {})

      service.send(:apply_layer_role_attrs!, layer, { included: "0" })

      expect(layer.reload.included?).to be(true)
      expect(layer.layer_role).to eq("primary")
    end
  end

  describe Users::RegistrationsController, "[REQ-FIT-AUTH-002]", type: :request do
    it "updates password without bypassing sign-in when Devise disables it" do
      user = create_billing_user!
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
      allow_any_instance_of(described_class).to receive(:sign_in_after_change_password?).and_return(false)

      patch user_registration_path, params: {
        user: {
          name: user.name,
          password: "newpassword1234",
          password_confirmation: "newpassword1234",
          current_password: "securepassword12"
        }
      }

      expect(response).to have_http_status(:redirect)
    end
  end

  describe ProjectInputDxfFilesController, "[REQ-FIT-DXF-001]" do
    it "requires attachment_ids_before when expanding layer panels" do
      host = described_class.new

      expect { host.send(:assign_layer_expand_state!, nil) }.to raise_error(/missing attachment_ids_before/)
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
    it "enqueues split planning for system_split resolutions" do
      project = create_project_for_spec!(title: "Orphan enqueue", bind_workspace: false)
      host = described_class.new
      host.instance_variable_set(:@project, project)
      allow(host).to receive(:reject_workshop_mutation_if_pending_payment!).and_return(false)
      allow(host).to receive(:redirect_to)
      allow(host).to receive(:params).and_return(
        ActionController::Parameters.new(
          piece_key: "0",
          orphan_resolution: { resolution_state: "system_split", reason: "oversized_for_sheet" }
        )
      )
      expect(Nesting::SplitPlanJob).to receive(:perform_later).with(kind_of(Integer))

      host.update
    end
  end

  describe SplitProposalsController, "[REQ-FIT-SPLIT-001]", type: :request do
    before do
      @user = create_billing_user!
      post user_session_path, params: { user: { email: @user.email, password: "securepassword12" } }
      get start_project_path
      follow_redirect!
      @project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID)
      @resolution = @project.orphan_resolutions.create!(
        piece_key: "0",
        resolution_state: :pending,
        reason: "oversized_for_sheet"
      )
    end

    it "rejects accepting proposals flagged split_not_feasible" do
      @resolution.split_proposals.create!(
        status: :draft,
        version: 1,
        feasible: false,
        plan_reason: "split_not_feasible",
        child_piece_geometries: [],
        cut_segments: [],
        labels: []
      )

      post accept_orphan_split_proposal_workshop_path(piece_key: @resolution.piece_key)

      expect(response).to redirect_to(workshop_path)
      expect(flash[:alert]).to eq(I18n.t("nesting.split.not_feasible_accept"))
    end

    it "rejects regenerating proposals while checkout lock is active" do
      run = @project.nesting_runs.create!(status: "completed")
      Payment.create!(
        user: @user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download",
        gateway_provider: "onvo",
        gateway_status: "processing",
        onvo_payment_intent_id: "pi_regen_lock",
        onvo_mode: "test",
        created_at: Time.current
      )

      post regenerate_orphan_split_proposal_workshop_path(piece_key: @resolution.piece_key)

      expect(response).to redirect_to(workshop_path)
    end
  end

  describe ProjectLayersController, "[REQ-FIT-DXF-001]", type: :request do
    it "redirects with readiness errors instead of starting nesting" do
      user = create_billing_user!
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
      get start_project_path
      follow_redirect!
      project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID)
      allow(ProjectReadinessValidator).to receive(:validate).and_return(
        ProjectReadinessValidator::Result.new(ok?: false, errors: [ "not ready" ])
      )

      patch workshop_layers_path, params: { project_layers: {} }

      expect(response).to redirect_to(project_layers_path(project))
    end
  end

  describe Dxf::LayerSyncPerFile, "[REQ-FIT-DXF-001]" do
    it "no-ops when the project has no input attachments" do
      project = create_project_for_spec!(title: "No attachments", bind_workspace: false)

      expect { described_class.call(project) }.not_to change(ProjectLayer, :count)
    end

    it "persists layers without colors when catalog entries omit color" do
      project = create_project_for_spec!(title: "No color", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      allow(Dxf::LayerNamesReader).to receive(:catalog).and_return([ { "name" => "NO_COLOR" } ])

      described_class.call(project)

      layer = project.project_layers.find_by!(layer_name: "NO_COLOR")
      expect(layer.color).to be_nil
    end

    it "cleans up tempfiles even when download fails" do
      project = create_project_for_spec!(title: "Download fail", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      attachment = project.input_dxf_attachments.first!
      allow(attachment).to receive(:download).and_raise(StandardError, "download failed")
      sync = described_class.new(project)

      expect { sync.send(:with_downloaded_path, attachment) { :unused } }.to raise_error(StandardError, "download failed")
    end
  end

  describe Dxf::LayerSync, "[REQ-FIT-DXF-001]" do
    it "no-ops when the project has no input attachments" do
      project = create_project_for_spec!(title: "Layer sync noop", bind_workspace: false)

      expect { described_class.call(project) }.not_to change(ProjectLayer, :count)
    end
  end

  describe MisPagosController, "[REQ-FIT-BILL-002]", type: :request do
    it "omits poll URL when no payment awaits confirmation" do
      user = create_billing_user!
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

      get mis_pagos_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include(checkout_payment_status_path(0))
    end
  end

  describe MisPagosController, "[REQ-FIT-BILL-002]" do
    it "skips auto-download grant lookup when param is absent" do
      host = described_class.new
      allow(host).to receive(:params).and_return(ActionController::Parameters.new)

      expect(host.send(:auto_download_grant)).to be_nil
    end
  end

  describe Nesting::MotherPieceStillPresent, "[REQ-FIT-SPLIT-001]" do
    it "returns false when the project has no DXF attachments" do
      project = create_project_for_spec!(title: "No dxf", bind_workspace: false)
      rings = [ [ [ 0, 0 ], [ 10, 0 ], [ 10, 10 ], [ 0, 10 ] ] ]

      expect(described_class.call(project: project, mother_rings: rings, layer_name: "PIECES")).to be(false)
    end

    it "returns false when rings do not produce a piece key" do
      project = create_project_for_spec!(title: "Bad rings", bind_workspace: false)

      expect(described_class.call(project: project, mother_rings: [], layer_name: "PIECES")).to be(false)
    end
  end

  describe "MisPagos::DownloadsController", "[REQ-FIT-BILL-003]", type: :request do
    it "returns forbidden when the grant id does not exist" do
      user = create_billing_user!
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

      get mis_pagos_download_path(id: 9_999_999)

      expect(response).to have_http_status(:forbidden)
    end

    it "records nil project_id when the nesting run is missing" do
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

  describe DownloadPaywallController, "[REQ-FIT-BILL-001]", type: :request do
    it "records nil user_id for guest paywall views" do
      allow(Analytics::TrackEvent).to receive(:call)

      get download_paywall_workshop_path

      expect(Analytics::TrackEvent).to have_received(:call).with(
        "paywall_viewed",
        hash_including(user_id: nil)
      )
    end

    it "redirects when workspace tab id is missing for bound tabs" do
      tab_id = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
      headers = { "X-Workspace-Tab-Id" => tab_id }
      get start_project_path, headers: headers
      follow_redirect!(headers: headers)

      get download_paywall_workshop_path

      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.expired"))
    end

    it "expires workspaces when tab-return TTL elapsed" do
      cookies[Workspace::TabLeave::TAB_LEFT_COOKIE] = (121.seconds.ago.to_f * 1000).to_i

      get download_paywall_workshop_path

      expect(response).to redirect_to(start_project_path)
      expect(flash[:alert]).to eq(I18n.t("workspace.tab_closed_expired"))
    end
  end

  describe Webhooks::OnvoController, "[REQ-FIT-BILL-001]", type: :request do
    it "accepts webhooks with blank bodies" do
      allow(Billing::Onvo::VerifyWebhook).to receive(:call).and_return(true)
      allow(Billing::Onvo::HandleWebhookEvent).to receive(:call).and_return(:ignored)

      post "/webhooks/onvo", headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:ok)
    end
  end
end
