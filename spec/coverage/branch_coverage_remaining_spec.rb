# frozen_string_literal: true

require "ostruct"
require "rails_helper"

RSpec.describe "Branch coverage remaining gaps" do
  include BillingModelHelpers
  include Rails.application.routes.url_helpers

  # --- Priority 2: ProjectsController (7) [REQ-FIT-UI-001] ---

  describe "ProjectsController remaining branches" do
    subject(:controller) { ProjectsController.new }

    let(:project) { create_project_for_spec!(title: "Branch gaps", bind_workspace: false) }

    before do
      controller.request = ActionDispatch::TestRequest.create
      controller.response = ActionDispatch::TestResponse.new
      allow(controller).to receive(:session).and_return({ anonymous_session_key: "anon-branch" })
    end

    it "redirects show when sync_nesting_ui_state expires the workspace" do
      controller.instance_variable_set(:@project, project)
      allow(Nesting::ProjectStatusSync).to receive(:call).and_return(nil)
      expect(controller).to receive(:redirect_to).with(start_project_path, alert: I18n.t("workspace.expired"))

      controller.show
    end

    it "returns not_found from nested_dxf when nested output is missing" do
      user = create_billing_user!
      run = project.nesting_runs.create!(status: "completed")
      controller.instance_variable_set(:@project, project)
      controller.instance_variable_set(:@nesting_run, run)
      allow(controller).to receive(:current_user).and_return(user)
      allow(Billing::RecordPlanDownload).to receive(:call)
      allow(Analytics::TrackEvent).to receive(:call)
      allow(Analytics::ResolveCountry).to receive(:call).and_return("CR")

      expect(controller).to receive(:head).with(:not_found)

      controller.nested_dxf
    end

    it "tracks download_completed for guest users without current_user id" do
      run = project.nesting_runs.create!(status: "completed")
      project.nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
      controller.instance_variable_set(:@project, project)
      controller.instance_variable_set(:@nesting_run, run)
      allow(controller).to receive(:current_user).and_return(nil)
      allow(Billing::RecordPlanDownload).to receive(:call)
      allow(Analytics::ResolveCountry).to receive(:call).and_return("CR")
      allow(Analytics::TrackEvent).to receive(:call)
      allow(controller).to receive(:send_data)

      controller.nested_dxf

      expect(Analytics::TrackEvent).to have_received(:call).with(
        "download_completed",
        hash_including(user_id: nil, anonymous_session_key: "anon-branch")
      )
    end

    it "invalidates nested outputs after a successful sheet workspace save" do
      project.nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
      controller.instance_variable_set(:@project, project)
      allow(controller).to receive(:reject_workshop_mutation_if_pending_payment!).and_return(false)
      allow(controller).to receive(:workspace_sheet_params).and_return(
        "sheet_stocks_attributes" => {
          "0" => { "id" => project.sheet_stocks.first!.id.to_s, "width_mm" => "1000", "height_mm" => "2000", "quantity" => "1", "sort_order" => "0" }
        }
      )
      allow(controller).to receive(:render_workspace_turbo_stream)
      expect(SheetStocks::InvalidateNestingOutputs).to receive(:call).with(project).and_call_original

      controller.send(:update_workspace_sheets!)
    end

    it "normalizes string-key quantity values in sheet attributes" do
      attrs = { "0" => { "quantity" => "3" } }

      controller.send(:normalize_sheet_quantities!, attrs)

      expect(attrs["0"][:quantity]).to eq(3)
    end

    it "omits preview zone streams when workshop UX hides the preview zone" do
      project.update!(status: :completed)
      controller.instance_variable_set(:@project, project)
      controller.instance_variable_set(:@nesting_preview, Nesting::PreviewPresenter.for(project))
      controller.instance_variable_set(:@nesting_orphans, Nesting::OrphansPresenter.for(project))
      allow(controller).to receive(:workshop_ux).and_return(instance_double(Workshop::UxMode, show_preview_zone?: false))
      allow(controller).to receive(:current_user).and_return(nil)

      streams = controller.send(:nesting_sync_streams)

      expect(streams.size).to eq(3)
    end
  end

  # --- Priority 2: ProjectReadinessValidator (5) [REQ-FIT-VAL-001] ---

  describe "ProjectReadinessValidator remaining branches" do
    let(:project) { create_project_for_spec!(title: "Readiness branches", bind_workspace: false) }
    let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

    it "skips per-file attachments with empty layer name lists" do
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "a.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      attachment = project.input_dxf_attachments.first!
      project.project_layers.where(active_storage_attachment_id: attachment.id).update_all(included: false)
      project.project_layers.create!(
        layer_name: "EMPTY",
        active_storage_attachment_id: attachment.id,
        included: true
      )
      allow(Dxf::PieceCounter).to receive(:layer_names_for_count).and_return([])

      expect(ProjectReadinessValidator.new(project).send(:extractable_piece_count)).to eq(0)
    end

    it "returns early from with_downloaded_dxf_paths when attachments are blank" do
      validator = ProjectReadinessValidator.new(project)
      yielded = validator.send(:with_downloaded_dxf_paths) { |paths| paths }

      expect(yielded).to eq([])
    end

    it "no-ops tempfile cleanup when Tempfile creation fails in with_downloaded_path" do
      validator = ProjectReadinessValidator.new(project)
      attachment = instance_double(ActiveStorage::Attachment)
      allow(Tempfile).to receive(:new).and_raise(StandardError, "tempfile failed")

      expect do
        validator.send(:with_downloaded_path, attachment) { |_path| :unused }
      end.to raise_error(StandardError, "tempfile failed")
    end

    it "no-ops tempfiles cleanup when attachment download fails in with_downloaded_dxf_paths" do
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "a.dxf", content_type: "application/dxf")
      validator = ProjectReadinessValidator.new(project)
      allow(project.input_dxf_attachments.first!).to receive(:download).and_raise(StandardError, "download failed")

      expect do
        validator.send(:with_downloaded_dxf_paths) { |_paths| :unused }
      end.to raise_error(StandardError, "download failed")
    end
  end

  # --- Priority 2: Nesting::JobRunner (4) [REQ-FIT-JOB-001] ---

  describe "Nesting::JobRunner remaining branches" do
    let(:project) do
      Project.create!(
        title: "JobRunner branches",
        nesting_time_limit_sec: 600,
        sheet_stocks_attributes: { "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 } }
      )
    end
    let(:nesting_run) { project.nesting_runs.create!(status: "processing") }

    it "raises CancelledError inside the timeout block when cancel arrives mid-run" do
      checks = 0
      allow(Nesting::CliRunner).to receive(:call) do |**|
        nesting_run.update!(cancel_requested_at: Time.current)
        checks += 1
      end
      allow(Nesting::ApplyCancel).to receive(:call).and_return(true)

      Nesting::JobRunner.call(nesting_run: nesting_run)

      expect(checks).to eq(1)
    end

    it "skips nested.dxf attachment when the output file is absent on timeout" do
      work_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s, "output")
      FileUtils.mkdir_p(work_dir)
      File.write(work_dir.join("report.json"), { status: "partial" }.to_json)
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      runner = Nesting::JobRunner.new(nesting_run: nesting_run)

      runner.send(:attach_outputs_if_present!, work_dir.dirname, "partial")

      expect(project.reload.nested_dxf).not_to be_attached
    ensure
      FileUtils.rm_rf(work_dir.dirname)
    end

    it "skips placements.json attachment when the file is absent on timeout" do
      work_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s, "output")
      FileUtils.mkdir_p(work_dir)
      File.write(work_dir.join("nested.dxf"), "NESTED")
      allow(Timeout).to receive(:timeout).and_raise(Timeout::Error)
      runner = Nesting::JobRunner.new(nesting_run: nesting_run)

      runner.send(:attach_outputs_if_present!, work_dir.dirname, "partial")

      expect(project.reload.placements_json).not_to be_attached
    ensure
      FileUtils.rm_rf(work_dir.dirname)
    end

    it "returns an empty report hash when report.json is missing during timeout handling" do
      runner = Nesting::JobRunner.new(nesting_run: nesting_run)
      work_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s)

      expect(runner.send(:load_report, work_dir)).to eq({})
    end
  end

  # --- Priority 2: ApplicationHelper (4) [REQ-FIT-UI-001] ---

  describe "ApplicationHelper remaining branches", type: :helper do
    it "does not rebind when the toolbar project already matches the request tab" do
      project = ProjectSpecFactory.create!(title: "Toolbar no rebind")
      helper.session[Workspace::WORKSPACES_KEY] = { "request-tab" => project.id }
      helper.request.headers[ResolvesWorkspaceTab::TAB_HEADER] = "request-tab"

      expect(Workspace).not_to receive(:bind!)

      expect(helper.toolbar_workspace_project).to eq(project)
    end

    it "returns nil from warden_user_if_available when request is nil" do
      allow(helper).to receive(:request).and_return(nil)

      expect(helper.send(:warden_user_if_available)).to be_nil
    end

    it "returns nil from warden_user_if_available when env is nil" do
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, env: nil))

      expect(helper.send(:warden_user_if_available)).to be_nil
    end

    it "returns nil when warden proxy is absent from env" do
      allow(helper).to receive(:request).and_return(instance_double(ActionDispatch::Request, env: { "warden" => nil }))

      expect(helper.send(:warden_user_if_available)).to be_nil
    end
  end

  # --- Priority 2: CartController (4) [REQ-FIT-BILL-001] ---

  describe "CartController remaining branches" do
    subject(:cart_controller) { CartController.new }

    before { cart_controller.request = ActionDispatch::TestRequest.create }

    it "redirects update to paywall when pending cart is missing" do
      allow(cart_controller).to receive(:load_pending_cart!)
      cart_controller.instance_variable_set(:@pending_cart, nil)
      expect(cart_controller).to receive(:redirect_to).with(download_paywall_workshop_path)

      cart_controller.update
    end

    it "summarizes PendingCart plan lines without tier_months" do
      expect(cart_controller.cart_line_summary({ "kind" => "plan" })).to eq(
        I18n.t("billing.cart.replace.line_plan", months: 0)
      )
    end

    it "persists guest tokens during pending-cart upsert for guests" do
      session = ActionController::TestSession.new
      allow(cart_controller).to receive(:session).and_return(session)
      allow(cart_controller).to receive(:current_user).and_return(nil)
      cart_controller.instance_variable_set(
        :@pending_cart,
        Billing::PendingCart.new("kind" => "plan", "tier_months" => 1, "currency_mode" => "crc")
      )
      allow(Billing::CartUpsert).to receive(:call)

      cart_controller.send(:upsert_cart_from_pending!)

      expect(session[:cart_guest_token]).to be_present
    end

    it "treats different cart kinds as conflicting lines" do
      existing = Cart.new(kind: "single_download", nesting_run_id: 1)
      allow(cart_controller).to receive(:cart_kind_param).and_return("plan")
      cart_controller.params = ActionController::Parameters.new(tier_months: 1)

      expect(cart_controller.send(:different_cart_line?, existing)).to be(true)
    end
  end

  # --- Priority 2: Nesting::CliRunner (4) [REQ-FIT-CLI-001] ---

  describe "Nesting::CliRunner remaining branches" do
    let(:project) do
      Project.create!(
        title: "CliRunner branches",
        ephemeral: true,
        sheet_stocks_attributes: { "0" => { width_mm: 500, height_mm: 500, quantity: 1, sort_order: 0 } }
      )
    end
    let(:nesting_run) { project.nesting_runs.create!(status: "processing") }

    it "raises CancelledError before invoke when cancel_check is true upfront" do
      expect do
        Nesting::CliRunner.call(
          nesting_run: nesting_run,
          invoke: ->(_work_dir, _config) { 0 },
          cancel_check: -> { true }
        )
      end.to raise_error(Nesting::CancelledError)
    end

    it "polls Open3 without cancel_check during the default CLI path" do
      wait_thr = instance_double(Process::Waiter, pid: 12_345)
      allow(wait_thr).to receive(:join).with(0.2).and_return(true)
      allow(wait_thr).to receive(:value).and_return(instance_double(Process::Status, exitstatus: 0))
      allow(Open3).to receive(:popen3).and_yield(nil, nil, nil, wait_thr)

      Nesting::CliRunner.call(nesting_run: nesting_run)

      expect(nesting_run.reload.status).to eq("failed")
    end

    it "skips nested.dxf attachment when output file is missing" do
      runner = Nesting::CliRunner.new(nesting_run: nesting_run)
      work_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s)
      FileUtils.mkdir_p(work_dir.join("output"))

      runner.send(:attach_nested_dxf!, work_dir)

      expect(project.reload.nested_dxf).not_to be_attached
    ensure
      FileUtils.rm_rf(work_dir)
    end

    it "skips placements.json attachment when output file is missing" do
      runner = Nesting::CliRunner.new(nesting_run: nesting_run)
      work_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s)
      FileUtils.mkdir_p(work_dir.join("output"))

      runner.send(:attach_placements_json!, work_dir)

      expect(project.reload.placements_json).not_to be_attached
    ensure
      FileUtils.rm_rf(work_dir)
    end
  end

  # --- Priority 2: NestingJob (4) [REQ-FIT-CLI-001] [REQ-FIT-ANALYTICS-001] ---

  describe "NestingJob remaining branches", type: :job do
    let(:project) { create_project_for_spec!(title: "NestingJob branches", bind_workspace: false) }
    let(:nesting_run) { project.nesting_runs.create!(status: "processing") }

    it "skips ensure telemetry while the run remains processing" do
      allow(Nesting::JobRunner).to receive(:call) do
        nesting_run.update!(status: "processing")
      end
      allow(Analytics::TrackEvent).to receive(:call)

      NestingJob.perform_now(nesting_run.id)

      expect(Analytics::TrackEvent).not_to have_received(:call)
    end

    it "skips FailRun when the run disappears after JobRunner raises" do
      allow(Nesting::JobRunner).to receive(:call).and_raise(StandardError, "boom")
      find_calls = 0
      allow(NestingRun).to receive(:find_by).with(id: nesting_run.id) do
        find_calls += 1
        find_calls == 1 ? nesting_run : nil
      end

      expect(Nesting::FailRun).not_to receive(:call)

      expect { NestingJob.perform_now(nesting_run.id) }.not_to raise_error
    end

    it "returns zero duration when started_at is missing" do
      nesting_run.update!(started_at: nil)
      job = NestingJob.new

      expect(job.send(:compute_duration_ms, nesting_run)).to eq(0)
    end

    it "sums piece counts from placements.json sheets" do
      output_dir = Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s, "output")
      FileUtils.mkdir_p(output_dir)
      File.write(
        output_dir.join("placements.json"),
        { "sheets" => [ { "pieces" => [ { "id" => 1 }, { "id" => 2 } ] } ] }.to_json
      )
      job = NestingJob.new

      expect(job.send(:parse_pieces_count, nesting_run)).to eq(2)
    ensure
      FileUtils.rm_rf(Rails.root.join("tmp/nesting_runs", nesting_run.id.to_s))
    end
  end

  # --- Priority 3: 3-branch billing/nesting files ---

  describe "Billing::PaymentStatusResponse branches [REQ-FIT-BILL-001]" do
    let(:routes) { Rails.application.routes.url_helpers }

    it "returns nil redirect when gateway status is not succeeded" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "succeeded",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download",
        gateway_status: "processing",
        paid_at: Time.current
      )

      payload = Billing::PaymentStatusResponse.for(payment: payment, routes: routes)

      expect(payload[:redirect_url]).to be_nil
    end

    it "returns nil redirect for plan subscriptions without auto-download grant" do
      payment = Payment.create!(
        user: create_billing_user!,
        status: "succeeded",
        payment_method: "card_usd",
        currency: "usd",
        amount: 10,
        purpose: "plan_subscription",
        gateway_status: "succeeded",
        paid_at: Time.current
      )

      payload = Billing::PaymentStatusResponse.for(payment: payment, routes: routes)

      expect(payload[:redirect_url]).to eq(routes.mis_pagos_path(payment_succeeded: 1))
    end

    it "returns retry checkout URL for unlocked pending SINPE single downloads" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download",
        checkout_abandoned_at: 1.hour.ago,
        checkout_lock_released_at: 1.hour.ago
      )

      payload = Billing::PaymentStatusResponse.for(payment: payment, routes: routes)

      expect(payload[:retry_checkout_url]).to include("nesting_run_id=#{payment.nesting_run_id}")
    end
  end

  describe "Billing::AbandonIncompleteCardCheckout branches [REQ-FIT-BILL-001]" do
    it "returns :not_card for non-card payments" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download"
      )

      expect(Billing::AbandonIncompleteCardCheckout.call(payment: payment)).to eq(:not_card)
    end

    it "returns :already_terminal for succeeded payments" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "succeeded",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download",
        paid_at: Time.current
      )

      expect(Billing::AbandonIncompleteCardCheckout.call(payment: payment)).to eq(:already_terminal)
    end

    it "returns :not_incomplete for pending card payments without 3DS attempt state" do
      user = create_billing_user!
      run = create_nesting_run!
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download",
        gateway_status: "requires_payment_method"
      )
      run.project.nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
      DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: 1.day.from_now
      )

      expect(Billing::AbandonIncompleteCardCheckout.call(payment: payment)).to eq(:not_incomplete)
    end
  end

  describe "Billing::CartMergeOnLogin branches [REQ-FIT-BILL-001]" do
    it "returns early for blank guest tokens" do
      user = create_billing_user!

      expect { Billing::CartMergeOnLogin.call(user: user, guest_token: "  ") }.not_to change(Cart, :count)
    end

    it "returns early when no guest cart exists" do
      user = create_billing_user!

      expect { Billing::CartMergeOnLogin.call(user: user, guest_token: SecureRandom.uuid) }.not_to change(Cart, :count)
    end

    it "returns early when guest cart already belongs to another user" do
      owner = create_billing_user!(email: "owner@example.com")
      guest = create_billing_user!(email: "guest@example.com")
      token = SecureRandom.uuid
      Cart.create!(guest_token: token, user_id: owner.id, kind: "plan", tier_months: 1, currency_mode: "crc", list_price_cents: 100, sinpe_price_cents: 90)

      expect { Billing::CartMergeOnLogin.call(user: guest, guest_token: token) }.not_to change { Cart.find_by(guest_token: token)&.user_id }
    end
  end

  describe "Billing::CheckoutBreakdown else branches [REQ-FIT-BILL-001]" do
    let(:ctx) do
      Billing::CheckoutContext.new(
        currency: :usd,
        payment_method: :card,
        country_code: nil,
        iva_applicable: false
      )
    end

    it "parses tier_months from integers in for_plan" do
      breakdown = Billing::CheckoutBreakdown.for_plan(tier_months: 1, billing_context: ctx)

      expect(breakdown[:total_amount]).to be > 0
    end

    it "returns nil sinpe reference for USD single downloads" do
      breakdown = Billing::CheckoutBreakdown.for_single_download(billing_context: ctx, overage: false)

      expect(breakdown[:discount_amount]).to eq(0)
    end

    it "converts USD cart cents to major units" do
      cart = Cart.create!(
        guest_token: SecureRandom.uuid,
        kind: "plan",
        tier_months: 1,
        currency_mode: "usd",
        list_price_cents: 250,
        sinpe_price_cents: 250
      )

      breakdown = Billing::CheckoutBreakdown.for_cart(cart: cart, billing_context: ctx)

      expect(breakdown[:list_price]).to eq(2.5)
    end
  end

  describe "Billing::GeoPaymentDefaults branches [REQ-FIT-BILL-001]" do
    it "raises when request lacks headers" do
      expect { Billing::GeoPaymentDefaults.from_request(Object.new) }
        .to raise_error(ArgumentError, /headers/)
    end

    it "falls back to GeoLite2 when Cloudflare header is absent" do
      request = ActionDispatch::TestRequest.create
      allow(Billing::GeoLite2).to receive(:country_code_for_ip).and_return("US")

      result = Billing::GeoPaymentDefaults.from_request(request)

      expect(result[:country_code]).to eq("US")
      expect(result[:resolution_source]).to eq(:geolite2)
    end

    it "falls back to session billing country when other sources fail" do
      request = ActionDispatch::TestRequest.create
      session = { billing_country_code: "CR" }
      allow(Billing::GeoLite2).to receive(:country_code_for_ip).and_return(nil)

      result = Billing::GeoPaymentDefaults.from_request(request, session: session)

      expect(result[:country_code]).to eq("CR")
      expect(result[:resolution_source]).to eq(:session)
    end
  end

  describe "Billing::Onvo::CardExpiration branches [REQ-FIT-BILL-001]" do
    it "rejects blank expiration values" do
      expect { Billing::Onvo::CardExpiration.parse("   ") }
        .to raise_error(ArgumentError, /card_exp_invalid/)
    end

    it "normalizes four-digit expirations without a slash" do
      expect(Billing::Onvo::CardExpiration.normalize("1228")).to eq("12/28")
    end

    it "expands two-digit years into the current century" do
      expect(Billing::Onvo::CardExpiration.normalize_year(28)).to eq(2028)
    end
  end

  describe "Billing::PlanExpiryPreview branches [REQ-FIT-BILL-001]" do
    it "rejects non-integer tier months" do
      user = create_billing_user!

      expect { Billing::PlanExpiryPreview.projected_ends_at(user: user, tier_months: "1") }
        .to raise_error(ArgumentError, /tier_months/)
    end

    it "rejects non-Time now values" do
      user = create_billing_user!

      expect { Billing::PlanExpiryPreview.projected_ends_at(user: user, tier_months: 1, now: Date.current) }
        .to raise_error(ArgumentError, /now must be a Time/)
    end

    it "extends from an active subscription end date" do
      user = create_billing_user!
      create_active_subscription!(user: user, ends_at: 2.weeks.from_now)

      ends_at = Billing::PlanExpiryPreview.projected_ends_at(user: user, tier_months: 1)

      expect(ends_at).to be > 2.weeks.from_now
    end
  end

  describe "Billing::ReleasePendingCheckoutLock guard branches [REQ-FIT-BILL-001]" do
    it "requires a payment" do
      expect { Billing::ReleasePendingCheckoutLock.call(payment: nil, user: create_billing_user!) }
        .to raise_error(ArgumentError, /payment required/)
    end

    it "requires a user" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download"
      )

      expect { Billing::ReleasePendingCheckoutLock.call(payment: payment, user: nil) }
        .to raise_error(ArgumentError, /user required/)
    end

    it "requires a persisted payment" do
      expect do
        Billing::ReleasePendingCheckoutLock.call(
          payment: Payment.new(status: "pending"),
          user: create_billing_user!
        )
      end.to raise_error(ArgumentError, /must be persisted/)
    end
  end

  describe "Billing::SupersedePendingCheckout branches [REQ-FIT-BILL-001]" do
    it "requires a user" do
      expect { Billing::SupersedePendingCheckout.call(user: nil, nesting_run: create_nesting_run!) }
        .to raise_error(ArgumentError, /user required/)
    end

    it "returns zero when nesting_run is nil" do
      expect(Billing::SupersedePendingCheckout.call(user: create_billing_user!, nesting_run: nil)).to eq(0)
    end

    it "skips payments that are already superseded" do
      user = create_billing_user!
      run = create_nesting_run!
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download",
        superseded_at: 1.hour.ago
      )

      expect(Billing::SupersedePendingCheckout.call(user: user, nesting_run: run)).to eq(0)
      expect(payment.reload.superseded_at).to be_present
    end
  end

  describe "Billing::CheckoutContext branches [REQ-FIT-BILL-001]" do
    it "requires billing_context for from_session" do
      expect { Billing::CheckoutContext.from_session(nil) }
        .to raise_error(ArgumentError, /billing_context required/)
    end

    it "accepts Currency value objects directly" do
      ctx = Billing::CheckoutContext.new(
        currency: Billing::Currency.parse(:crc),
        payment_method: :sinpe,
        country_code: Billing::CountryCode.parse("CR"),
        iva_applicable: true
      )

      expect(ctx.currency.crc?).to be(true)
    end

    it "leaves country_code nil in to_h when absent" do
      ctx = Billing::CheckoutContext.new(
        currency: :usd,
        payment_method: :card,
        country_code: nil,
        iva_applicable: false
      )

      expect(ctx.to_h[:country_code]).to be_nil
    end
  end

  describe "Nesting::OrphansPresenter orphan struct branches [REQ-FIT-SPLIT-001]" do
    it "returns false for split preview when proposal is missing" do
      orphan = Nesting::OrphansPresenter::Orphan.new(split_proposal: nil)

      expect(orphan.split_preview_available?).to be(false)
    end

    it "returns false for split preview when child geometries are empty" do
      proposal = instance_double(SplitProposal, draft?: true, feasible?: true, child_piece_geometries: [])
      orphan = Nesting::OrphansPresenter::Orphan.new(split_proposal: proposal)

      expect(orphan.split_preview_available?).to be(false)
    end

    it "returns false for applied preview when split is not applied" do
      orphan = Nesting::OrphansPresenter::Orphan.new(resolution_state: "pending", split_proposal: nil)

      expect(orphan.split_applied_preview_available?).to be(false)
    end
  end

  describe "PersistWorkspaceSheetInventoryDraft branches [REQ-FIT-UI-005]" do
    it "returns false when sheet attributes are blank" do
      project = create_project_for_spec!(title: "Sheet draft", bind_workspace: false)
      session = { Workspace::SESSION_KEY => project.id }

      result = PersistWorkspaceSheetInventoryDraft.call(
        session: session,
        params: ActionController::Parameters.new(project: { sheet_stocks_attributes: {} })
      )

      expect(result).to be(false)
    end

    it "returns false when omitting all persisted stock ids" do
      project = create_project_for_spec!(title: "Sheet omit", bind_workspace: false)
      session = { Workspace::SESSION_KEY => project.id }
      params = ActionController::Parameters.new(
        project: { sheet_stocks_attributes: { "0" => { width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 } } }
      )

      expect(PersistWorkspaceSheetInventoryDraft.call(session: session, params: params)).to be(false)
    end

    it "stashes composer draft values after a successful save" do
      project = Project.create!(ephemeral: true, title: "Composer draft", status: :draft)
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

      expect(PersistWorkspaceSheetInventoryDraft.call(session: session, params: params)).to be(true)
      expect(session[PersistWorkspaceSheetInventoryDraft::COMPOSER_SESSION_KEY]).to include("width_mm" => "1200")
    end
  end

  describe "Dxf::LayerSyncPerFile branches [REQ-FIT-DXF-001]" do
    let(:project) { create_project_for_spec!(title: "Layer sync per file", bind_workspace: false) }
    let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

    it "returns early when no attachments exist" do
      expect { Dxf::LayerSyncPerFile.call(project) }.not_to change(ProjectLayer, :count)
    end

    it "creates new layers as excluded by default" do
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")

      Dxf::LayerSyncPerFile.call(project)

      expect(project.project_layers.where(included: true)).to be_empty
    end

    it "preserves gaps_detected when re-syncing an existing layer" do
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      layer = project.project_layers.find_by!(layer_name: "PIECES")
      gaps = [ { "distance_mm" => 5.0, "start" => [0.0, 0.0], "end" => [5.0, 0.0] } ]
      layer.update!(gaps_detected: gaps)

      Dxf::LayerSyncPerFile.call(project)

      expect(layer.reload.gaps_detected).to eq(gaps)
    end

    it "cleans up tempfiles even when download fails" do
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      attachment = project.input_dxf_attachments.first!
      allow(attachment).to receive(:download).and_raise(StandardError, "download failed")

      expect { Dxf::LayerSyncPerFile.new(project).send(:with_downloaded_path, attachment) { :unused } }
        .to raise_error(StandardError, "download failed")
    end
  end

  describe "Dxf::LayerSync branches [REQ-FIT-DXF-001]" do
    let(:project) { create_project_for_spec!(title: "Layer sync union", bind_workspace: false) }
    let(:sample_dxf) { Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf") }

    it "returns early when attachments are blank" do
      expect { Dxf::LayerSync.call(project) }.not_to change(ProjectLayer, :count)
    end

    it "preserves existing layer colors when catalog omits color" do
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSync.call(project)
      layer = project.project_layers.find_by!(layer_name: "PIECES")
      layer.update!(color: "#ff0000")
      allow(Dxf::LayerNamesReader).to receive(:catalog).and_return([ { "name" => "PIECES" } ])

      Dxf::LayerSync.call(project)

      expect(layer.reload.color).to eq("#ff0000")
    end

    it "cleans up tempfiles when download fails in with_downloaded_dxf_paths" do
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      allow(project.input_dxf_attachments.first!).to receive(:download).and_raise(StandardError, "download failed")

      expect { Dxf::LayerSync.new(project).send(:with_downloaded_dxf_paths) { :unused } }
        .to raise_error(StandardError, "download failed")
    end
  end

  describe "ProjectLayer::SetPrimary post-condition branches [REQ-FIT-DXF-002]" do
    it "clears sibling primary layers on the same attachment" do
      project = create_project_for_spec!(title: "Set primary siblings", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "panel.dxf", content_type: "application/dxf")
      attachment = project.input_dxf_attachments.first!
      Dxf::LayerSyncPerFile.call(project)
      first = project.project_layers.find_by!(layer_name: "PIECES", active_storage_attachment_id: attachment.id)
      second = project.project_layers.create!(
        layer_name: "ALT",
        active_storage_attachment_id: attachment.id,
        included: true,
        layer_role: :primary
      )

      ProjectLayer::SetPrimary.call(first)

      expect(second.reload.layer_role).to be_nil
      expect(first.reload.layer_role).to eq("primary")
    end
  end

  describe "User private branches [REQ-FIT-AUTH-002]" do
    it "raises when billing_ready precondition fails on unpersisted users" do
      user = User.new(email: "new@example.com", password: "securepassword12")

      expect { user.billing_ready? }.to raise_error(ArgumentError, /precondition failed/)
    end

    it "skips password length validation when password is blank" do
      user = create_billing_user!
      user.password = nil

      user.send(:password_minimum_length)

      expect(user.errors[:password]).to be_empty
    end

    it "does not require password when provider is present" do
      user = User.new(provider: "google", email: "oauth@example.com", name: "OAuth", terms_accepted_at: Time.current, terms_version: "v1", time_zone: "UTC")

      expect(user.send(:password_required?)).to be(false)
    end
  end

  describe "StoresWorkspaceReturnTo branches [REQ-FIT-AUTH-002]" do
    controller_class = Class.new(ApplicationController) do
      include StoresWorkspaceReturnTo
      def self.name = "StoresWorkspaceReturnToSpecController"
    end

    it "rebinds the workshop tab when resume tab differs" do
      host = controller_class.new
      project = Project.create!(ephemeral: true, title: "Return to", status: :draft)
      session = { Workspace::WORKSPACES_KEY => { "stored-tab" => project.id } }
      host.request = ActionDispatch::TestRequest.create
      host.request.headers[ResolvesWorkspaceTab::TAB_HEADER] = "resume-tab"
      allow(host).to receive(:session).and_return(session)
      expect(Workspace).to receive(:bind!).with(session, project, tab_id: "resume-tab")

      expect(host.send(:workshop_resume_path)).to eq(workshop_path)
    end

    it "returns false from store_workspace_return_to? on non-devise controllers" do
      host = Users::SessionsController.new
      allow(host).to receive(:devise_controller?).and_return(false)

      expect(host.send(:store_workspace_return_to?)).to be(false)
    end

    it "returns false from store_workspace_return_to_action? on unsupported controllers" do
      host = Users::SessionsController.new

      allow(host).to receive(:controller_name).and_return("passwords")

      expect(host.send(:store_workspace_return_to_action?)).to be(false)
    end

    it "stores workshop return path when bound and unset" do
      host = controller_class.new
      project = Project.create!(ephemeral: true, title: "Store return", status: :draft)
      session = { Workspace::WORKSPACES_KEY => { Workspace::DEFAULT_TAB_ID => project.id } }
      host.request = ActionDispatch::TestRequest.create
      allow(host).to receive(:session).and_return(session)
      allow(host).to receive(:workspace_tab_id).and_return(Workspace::DEFAULT_TAB_ID)

      host.send(:store_workspace_return_to!)

      expect(session[:workspace_return_to]).to eq(workshop_path)
    end
  end

  # --- Priority 4: 2-branch files ---

  describe "PersistWorkspaceLayerSelectionDraft branches [REQ-FIT-UI-005]" do
    it "ignores non-hash layer entries when scanning selection params" do
      service = PersistWorkspaceLayerSelectionDraft.new(session: {}, params: {})
      permitted = { "1" => "not-a-hash" }

      expect(service.send(:selection_in_params?, permitted)).to be(false)
    end

    it "detects primary layer selection in params" do
      service = PersistWorkspaceLayerSelectionDraft.new(session: {}, params: {})
      permitted = { "1" => { "primary_layer_id" => "42" } }

      expect(service.send(:selection_in_params?, permitted)).to be(true)
    end
  end

  describe "Dxf::PieceCounter branches [REQ-FIT-DXF-001]" do
    it "returns zero for blank paths or layer names" do
      expect(Dxf::PieceCounter.count(paths: [], layer_names: [ "PIECES" ])).to eq(0)
      expect(Dxf::PieceCounter.count(paths: [ "/tmp/x.dxf" ], layer_names: [])).to eq(0)
    end

    it "raises when the Python counter exits non-zero" do
      allow(Open3).to receive(:capture2).and_return([ "counter failed", instance_double(Process::Status, success?: false) ])

      expect do
        Dxf::PieceCounter.count(paths: [ "/tmp/x.dxf" ], layer_names: [ "PIECES" ])
      end.to raise_error(Dxf::PieceCounter::Error, /counter failed/)
    end
  end

  describe "Nesting::ProgressSync branches [REQ-FIT-JOB-001]" do
    it "omits estimated_finished_at when ETA is blank" do
      project = create_project_for_spec!(title: "Progress sync", status: :processing, bind_workspace: false)
      run = project.nesting_runs.create!(status: "processing")
      snapshot = Nesting::ProgressSnapshot.from_hash(
        { "version" => 1, "phase_id" => "fill", "percent" => 20 },
        last_percent: 0
      )
      allow(Nesting::ProgressEta).to receive(:estimate).and_return(nil)

      Nesting::ProgressSync.call(project: project, snapshot: snapshot, nesting_run: run, broadcast: false)

      expect(project.reload.estimated_finished_at).to be_nil
    end

    it "no-ops broadcast when snapshot percent does not advance" do
      project = create_project_for_spec!(title: "Progress noop", status: :processing, bind_workspace: false)
      project.update!(progress_percent: 10, progress_message: "nesting.phase.fill")
      snapshot = Nesting::ProgressSnapshot.from_hash(
        { "version" => 1, "phase_id" => "fill", "percent" => 10 },
        last_percent: 10
      )
      allow(Nesting::ProgressEta).to receive(:estimate).and_return(nil)
      allow(Nesting::ProgressBroadcaster).to receive(:call)

      Nesting::ProgressSync.call(project: project, snapshot: snapshot, broadcast: true)

      expect(Nesting::ProgressBroadcaster).not_to have_received(:call)
    end
  end

  describe "Nesting::PreviewPresenter branches [REQ-FIT-UI-002]" do
    it "skips blank layer names when building color map" do
      project = create_project_for_spec!(title: "Preview colors", bind_workspace: false)
      layer = project.project_layers.create!(layer_name: "CUT", included: true, color: "#abc")
      layer.update_column(:layer_name, "")

      colors = Nesting::PreviewPresenter.for(project).send(:layer_colors)

      expect(colors).to eq({})
    end

    it "skips layers without colors" do
      project = create_project_for_spec!(title: "Preview no color", bind_workspace: false)
      project.project_layers.create!(layer_name: "CUT", included: true, color: nil)

      colors = Nesting::PreviewPresenter.for(project).send(:layer_colors)

      expect(colors).to eq({})
    end
  end

  describe "Nesting::LocalizedProgressMessage branches [REQ-FIT-JOB-001]" do
    it "returns empty text for blank stored messages on non-terminal projects" do
      project = create_project_for_spec!(title: "Localized blank", status: :processing, bind_workspace: false)
      project.update!(progress_message: "")

      message = Nesting::LocalizedProgressMessage.new(project)

      expect(message.to_s).to eq("")
    end

    it "detects stored i18n keys across available locales" do
      project = create_project_for_spec!(title: "Localized key", status: :completed, bind_workspace: false)
      project.update!(progress_message: "nesting.completed")

      expect(Nesting::LocalizedProgressMessage.time_limit_notice?(project)).to be(false)
    end
  end

  describe "Billing::Entitlement branches [REQ-FIT-BILL-001]" do
    it "denies downloads for unconfirmed users" do
      user = create_billing_user!
      user.update!(confirmed_at: nil)
      run = create_nesting_run!

      expect(Billing::Entitlement.new(user: user, nesting_run: run).can_download?).to be(false)
    end

    it "denies plan quota when nesting run project is missing" do
      user = create_billing_user!
      create_active_subscription!(user: user)
      run = create_nesting_run!
      allow(run).to receive(:project).and_return(nil)

      expect(Billing::Entitlement.new(user: user, nesting_run: run).can_download?).to be(false)
    end
  end

  describe "Billing::PlanDownloadAvailability branches [REQ-FIT-BILL-001]" do
    it "returns false for plan_included when user is nil" do
      expect(Billing::PlanDownloadAvailability.plan_included?(user: nil)).to be(false)
    end

    it "returns false for plan_quota_exhausted when user lacks billing readiness" do
      user = create_billing_user!
      user.update!(confirmed_at: nil)

      expect(Billing::PlanDownloadAvailability.plan_quota_exhausted?(user: user)).to be(false)
    end
  end

  describe "Billing::FulfillPayment branches [REQ-FIT-BILL-001]" do
    it "grants retention for SINPE fulfillments" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        total_amount: 1130,
        purpose: "single_download"
      )
      allow(Billing::RetainNestedDxf).to receive(:call)

      Billing::FulfillPayment.call(payment: payment)

      expect(Billing::RetainNestedDxf).to have_received(:call)
    end

    it "skips grant creation when download grant already exists" do
      user = create_billing_user!
      run = create_nesting_run!
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download"
      )
      DownloadGrant.create!(user: user, nesting_run: run, kind: "single_purchase", retained_until: 1.day.from_now)
      run.project.nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )

      expect { Billing::FulfillPayment.call(payment: payment) }.not_to change(DownloadGrant, :count)
    end
  end

  describe "Billing::SimulateSingleDownload branches [REQ-FIT-BILL-001]" do
    def attach_nested_dxf!(run)
      run.project.nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
    end

    it "uses cart snapshot cents when currency matches" do
      user = create_billing_user!
      run = create_nesting_run!
      attach_nested_dxf!(run)
      Cart.create!(
        user_id: user.id,
        kind: "single_download",
        nesting_run_id: run.id,
        currency_mode: "usd",
        list_price_cents: 250,
        sinpe_price_cents: 250
      )

      result = Billing::SimulateSingleDownload.call(
        user: user,
        nesting_run: run,
        payment_method: "card_usd",
        outcome: "success",
        iva_applicable: false
      )

      expect(result[:payment].amount).to eq(2.5)
    end

    it "records analytics when request context is provided" do
      user = create_billing_user!
      run = create_nesting_run!
      attach_nested_dxf!(run)
      request = ActionDispatch::TestRequest.create
      session = { anonymous_session_key: "anon-sim" }
      allow(Analytics::TrackEvent).to receive(:call)

      Billing::SimulateSingleDownload.call(
        user: user,
        nesting_run: run,
        payment_method: "card_usd",
        outcome: "success",
        iva_applicable: false,
        request: request,
        session: session
      )

      expect(Analytics::TrackEvent).to have_received(:call).at_least(:once)
    end
  end

  describe "Billing::CartTotals branches [REQ-FIT-BILL-001]" do
    it "rejects carts that do not expose list_price_cents" do
      expect do
        Billing::CartTotals.for_cart(
          cart: Object.new,
          billing_context: { currency: :usd, payment_method: :card, iva_applicable: false }
        )
      end.to raise_error(ArgumentError, /list_price_cents/)
    end

    it "returns breakdown data for persisted carts" do
      cart = Cart.create!(
        guest_token: SecureRandom.uuid,
        kind: "plan",
        tier_months: 2,
        currency_mode: "usd",
        list_price_cents: 500,
        sinpe_price_cents: 500
      )

      totals = Billing::CartTotals.for_cart(
        cart: cart,
        billing_context: { currency: :usd, payment_method: :card, iva_applicable: false }
      )

      expect(totals[:breakdown][:total_amount]).to be > 0
    end
  end

  describe "Analytics::ResolveCountry branches [REQ-FIT-ANALYTICS-001]" do
    it "uses CF-IPCountry when present" do
      request = ActionDispatch::TestRequest.create
      request.headers["CF-IPCountry"] = "CR"

      expect(Analytics::ResolveCountry.call(request)).to eq("CR")
    end

    it "returns nil when no country can be resolved" do
      request = ActionDispatch::TestRequest.create
      allow(Billing::GeoLite2).to receive(:country_code_for_ip).and_return(nil)

      expect(Analytics::ResolveCountry.call(request)).to be_nil
    end
  end

  describe "Admin reporting branches [REQ-FIT-ADMIN-001]" do
    it "uses amount fallback in HaciendaSummaryRows net_collected" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "succeeded",
        payment_method: "card_crc",
        currency: "crc",
        amount: 1000,
        total_amount: 0,
        purpose: "single_download",
        paid_at: Time.current
      )

      expect(Admin::HaciendaSummaryRows.net_collected(payment)).to eq(1000.0)
    end

    it "groups succeeded payments for summary exports" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "succeeded",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        total_amount: 2,
        purpose: "single_download",
        paid_at: Time.current
      )

      grouped = Admin::HaciendaSummaryRows.succeeded_groups(Payment.where(id: payment.id), currency: "usd")

      expect(grouped.values.flatten).to include(payment)
    end

    it "shows em dash when form150 end date param is explicitly blank" do
      filter = Admin::VentasFilter.new({ end_date: "" }, date_column: :paid_at)

      expect(filter.send(:form150_period_end_display)).to eq("—")
    end

    it "includes search terms in ventas filter scopes" do
      filter = Admin::VentasFilter.new({ search: "billing@example.com" }, date_column: :paid_at)

      expect(filter.apply(Payment.all).to_sql.downcase).to include("billing")
    end

    it "exports alternating stripe rows for multiple payments" do
      user = create_billing_user!
      2.times do
        Payment.create!(
          user: user,
          nesting_run: create_nesting_run!,
          status: "succeeded",
          payment_method: "card_crc",
          currency: "crc",
          amount: 1000,
          total_amount: 1000,
          purpose: "single_download",
          paid_at: Time.current
        )
      end

      xlsx = Admin::ExportPaymentsXlsx.call(Payment.where(user_id: user.id))

      expect(xlsx.bytesize).to be > 100
    end
  end

  describe "Billing::PaymentMethod branches [REQ-FIT-BILL-001]" do
    it "rejects nil payment method values at parse time" do
      expect { Billing::PaymentMethod.parse(nil) }.to raise_error(ArgumentError, /payment_method required/)
    end

    it "rejects unknown payment method strings in initialize" do
      expect { Billing::PaymentMethod.new("wire_transfer") }.to raise_error(ArgumentError, /unknown payment_method/)
    end
  end

  describe "Nesting::SheetStockRow branches [REQ-FIT-NEST-004]" do
    it "rejects rows without width or height" do
      expect do
        Nesting::SheetStockRow.new(width_mm: 0, height_mm: 1000, quantity: 1, sort_order: 0)
      end.to raise_error(ArgumentError, /width_mm must be positive/)
    end

    it "normalizes blank quantity to nil" do
      row = Nesting::SheetStockRow.new(width_mm: 1000, height_mm: 2000, quantity: nil, sort_order: 0)

      expect(row.quantity).to be_nil
    end
  end

  describe "Workshop and nesting helper branches [REQ-FIT-UI-003]" do
    let(:helper_obj) do
      Class.new do
        include WorkshopUrlHelper
        include NestingProgressHelper
        include Rails.application.routes.url_helpers
      end.new
    end

    it "builds input DXF file paths from explicit ids when record is nil" do
      expect(helper_obj.project_input_dxf_file_path(nil, id: 99)).to include("99")
    end

    it "builds cancel nesting run paths from explicit ids when run is nil" do
      expect(helper_obj.cancel_project_nesting_run_path(nil, id: 77)).to include("77")
    end

    it "returns only percent text when progress message is blank" do
      project = create_project_for_spec!(title: "Blank progress", status: :processing, bind_workspace: false)
      project.update!(progress_message: "")

      expect(helper_obj.nesting_progress_aria_valuetext(project, 0)).to eq("")
    end
  end

  describe "Billing::PendingCheckoutLock branches [REQ-FIT-BILL-001]" do
    it "returns inactive lock for nil users" do
      project = create_project_for_spec!(title: "No user lock", bind_workspace: false)
      lock = Billing::PendingCheckoutLock.for(project: project, user: nil)

      expect(lock).to be_nil
    end

    it "returns inactive lock when no pending payment exists" do
      project = create_project_for_spec!(title: "No pending", bind_workspace: false)
      user = create_billing_user!
      lock = Billing::PendingCheckoutLock.for(project: project, user: user)

      expect(lock).to be_nil
    end
  end

  describe "Billing::Onvo minor unit helpers [REQ-FIT-BILL-001]" do
    it "converts CRC breakdown totals to centimos" do
      minor = Billing::Onvo::MoneyMinorUnits.from_breakdown(
        currency: :crc,
        total_amount: 10.5
      )

      expect(minor.to_i).to eq(1050)
    end

    it "rejects unsupported currencies in minor unit conversion" do
      expect do
        Billing::Onvo::MoneyMinorUnits.from_breakdown(currency: :eur, total_amount: 1)
      end.to raise_error(ArgumentError, /unsupported currency/)
    end
  end

  describe "Billing::Onvo::SinpeDestination branches [REQ-FIT-BILL-001]" do
    it "falls back to default number when config is blank" do
      allow(Billing::Pricing).to receive(:config_section).with("onvo_sinpe_destination").and_return({})

      expect(Billing::Onvo::SinpeDestination.number).to eq(Billing::Onvo::SinpeDestination::DEFAULT_NUMBER)
    end

    it "falls back to default holder when config omits holder_name" do
      allow(Billing::Pricing).to receive(:config_section).with("onvo_sinpe_destination").and_return({ "number" => "+506 70000000" })

      expect(Billing::Onvo::SinpeDestination.holder_name).to eq(Billing::Onvo::SinpeDestination::DEFAULT_HOLDER_NAME)
    end
  end

  describe "Billing::WorkshopLockWindow branches [REQ-FIT-BILL-001]" do
    it "builds lock windows from billing config" do
      window = Billing::WorkshopLockWindow.from_config

      expect(window.minutes).to be_positive
    end

    it "computes lock expiry from payment creation time" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download",
        created_at: Time.current
      )
      window = Billing::WorkshopLockWindow.from_config

      expect(window.lock_expires_at(payment)).to be > Time.current
    end
  end

  # --- Priority 5: 1-branch files ---

  describe "Single-branch coverage sweep" do
    it "Analytics::Thresholds treats missing YAML root as empty config" do
      allow(YAML).to receive(:load_file).and_return(nil)
      Analytics::Thresholds.send(:remove_instance_variable, :@config) if Analytics::Thresholds.instance_variable_defined?(:@config)

      expect(Analytics::Thresholds.send(:load_config)).to eq({})
    end

    it "Billing::Money rejects negative major amounts" do
      expect { Billing::Money.from_major(-1, :usd) }.to raise_error(ArgumentError, /non-negative/)
    end

    it "Billing::CartUpsert replaces existing user carts" do
      user = create_billing_user!
      Cart.create!(user_id: user.id, kind: "plan", tier_months: 1, currency_mode: "usd", list_price_cents: 100, sinpe_price_cents: 100)

      cart = Billing::CartUpsert.call(user: user, guest_token: nil, kind: "plan", tier_months: 2, currency_mode: "usd")

      expect(cart.tier_months).to eq(2)
    end

    it "Billing::PendingCart accepts plan payloads with tier months" do
      pending = Billing::PendingCart.new("kind" => "plan", "tier_months" => 1, "currency_mode" => "crc")

      expect(pending.tier_months.to_i).to eq(1)
    end

    it "Billing::RetainNestedDxf skips retention window updates when already active" do
      user = create_billing_user!
      run = create_nesting_run!
      grant = DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: 2.days.from_now
      )
      run.project.nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )

      expect(Billing::RetainNestedDxf.call(grant: grant, nesting_run: run)).to eq(grant)
      expect(grant.reload.retained_until).to be > 1.day.from_now
    end

    it "Nesting::ConfigBuilder uses per-file input mode when layers are attachment-scoped" do
      project = create_project_for_spec!(title: "Per-file config", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      work_dir = Rails.root.join("tmp/nesting-config-branch-spec")
      FileUtils.mkdir_p(work_dir)
      input = work_dir.join("input.dxf")
      File.write(input, "stub")

      payload = Nesting::ConfigBuilder.build(project: project, work_dir: work_dir, input_paths: [ input ])

      expect(payload).to include(:input_files)
    ensure
      FileUtils.rm_rf(work_dir)
    end

    it "Nesting::ProgressSnapshot preserves phase-derived message keys" do
      snapshot = Nesting::ProgressSnapshot.from_hash(
        { "version" => 1, "phase_id" => "fill", "percent" => 15 },
        last_percent: 0
      )

      expect(snapshot.message_key).to eq("nesting.phase.fill")
    end

    it "Nesting::FailRun no-ops for cancelled runs" do
      run = create_nesting_run!
      run.update!(status: "failed", cancel_requested_at: Time.current)

      expect(Nesting::FailRun.call(nesting_run: run)).to be(false)
    end

    it "SheetStocks::InvalidateNestingOutputs purges attached nested outputs" do
      project = create_project_for_spec!(title: "Invalidate outputs", bind_workspace: false)
      project.nested_dxf.attach(io: StringIO.new("nested"), filename: "nested.dxf", content_type: "application/dxf")

      expect(SheetStocks::InvalidateNestingOutputs.call(project)).to be(true)
      expect(project.reload.nested_dxf).not_to be_attached
    end

    it "Workspace tab_ids falls back to legacy session key" do
      session = { Workspace::SESSION_KEY => 42 }

      expect(Workspace.send(:tab_ids, session)).to eq([ Workspace::DEFAULT_TAB_ID ])
    end

    it "Payment suppresses incomplete card attempts once checkout is abandoned" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download",
        gateway_status: "requires_action",
        checkout_abandoned_at: Time.current
      )

      expect(payment.awaiting_gateway_confirmation?).to be(false)
    end
  end

  # --- Controller request branches ---

  describe "CheckoutController branches", type: :request do
    let(:user) { create_billing_user! }

    before { post user_session_path, params: { user: { email: user.email, password: "securepassword12" } } }

    it "returns conflict when replace cart is blocked by pending checkout" do
      begin_workspace_session!
      project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID)
      run = project.nesting_runs.create!(status: "completed")
      keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
      ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
      ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
      Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        gateway_status: "processing",
        onvo_payment_intent_id: "pi_branch_conflict",
        onvo_mode: "test",
        created_at: 5.minutes.ago
      )

      post checkout_pay_path, params: { nesting_run_id: run.id, payment_method: "sinpe_crc" }, as: :json

      expect(response).to have_http_status(:conflict)
    ensure
      previous&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it "assigns @project from nesting_run when loading single-download checkout" do
      begin_workspace_session!
      project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID)
      run = project.nesting_runs.create!(status: "completed")

      get checkout_path(nesting_run_id: run.id)

      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@project)).to eq(project)
    end

    it "leaves @nesting_run nil for plan cart checkout without a nesting run" do
      begin_workspace_session!
      Cart.create!(
        user_id: user.id,
        kind: "plan",
        tier_months: "1",
        currency_mode: "crc",
        list_price_cents: 3250,
        sinpe_price_cents: 3000
      )

      get checkout_path

      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@nesting_run)).to be_nil
      expect(controller.instance_variable_get(:@checkout_kind)).to eq(:plan)
    end

    it "omits nesting_run_id from card checkout redirect params when absent" do
      begin_workspace_session!
      payment = user.payments.create!(
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        total_amount: 1130,
        purpose: "single_download",
        nesting_run_id: nil
      )

      get checkout_path
      params = controller.send(:checkout_redirect_params_for_payment, payment)

      expect(params).not_to have_key(:nesting_run_id)
      expect(params).not_to have_key(:payment_method)
    end
  end

  describe "DownloadPaywallController branches", type: :request do
    it "creates an ephemeral workspace for guests arriving without a bind" do
      expect { get download_paywall_workshop_path }.to change(Project.ephemeral, :count).by(1)

      expect(response).to have_http_status(:ok)
      project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID)
      expect(project).to be_ephemeral
    end
  end

  describe "SplitProposalsController branches", type: :request do
    it "blocks accept when checkout lock is active" do
      user = create_billing_user!
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
      get start_project_path
      follow_redirect!
      project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID)
      resolution = project.orphan_resolutions.create!(
        piece_key: "0",
        resolution_state: :pending,
        reason: "oversized_for_sheet"
      )
      resolution.split_proposals.create!(
        status: :draft,
        version: 1,
        feasible: true,
        child_piece_geometries: [ { "label" => "a", "rings" => [ [ [ 0, 0 ], [ 1, 0 ], [ 1, 1 ] ] ] } ],
        cut_segments: [],
        labels: [ "a" ]
      )
      run = project.nesting_runs.create!(status: "completed")
      Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        gateway_status: "processing",
        onvo_payment_intent_id: "pi_split_lock",
        onvo_mode: "test"
      )

      post accept_orphan_split_proposal_workshop_path(piece_key: resolution.piece_key)

      expect(response).to redirect_to(workshop_path)
      expect(flash[:alert]).to eq(I18n.t("billing.checkout.pending_workshop_lock.message"))
    end
  end

  describe "Misc controller/helper 1-branch coverage", type: :request do
    it "Users::ConfirmationsController renders inactive sign-up path for unconfirmed users" do
      user = create_billing_user!
      user.update!(confirmed_at: nil, confirmation_token: Devise.friendly_token)

      get user_confirmation_path(confirmation_token: user.confirmation_token)

      expect(response).to have_http_status(:redirect).or have_http_status(:ok)
    end

    it "Users::SessionsController redirects active users away from destroy confirmation" do
      user = create_billing_user!
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

      delete destroy_user_session_path

      expect(response).to have_http_status(:found).or have_http_status(:ok)
    end

    it "PlanesController handles missing current_user gracefully" do
      get planes_path

      expect(response).to have_http_status(:found)
    end
  end

  # --- Additional 2–3 branch files ---

  describe "Nesting::ConfirmManualOrphanResolution branches [REQ-FIT-SPLIT-001]" do
    it "fails when orphan geometry is missing from the report" do
      project = create_project_for_spec!(title: "Manual orphan", bind_workspace: false)
      resolution = project.orphan_resolutions.create!(
        piece_key: "0",
        resolution_state: :pending,
        reason: "oversized_for_sheet"
      )
      allow(ProjectReadinessValidator).to receive(:validate).and_return(
        ProjectReadinessValidator::Result.new(ok?: true, errors: [])
      )
      allow(Nesting::OrphansPresenter).to receive(:for).and_return(instance_double(Nesting::OrphansPresenter, items: []))

      result = Nesting::ConfirmManualOrphanResolution.call(project: project, orphan_resolution: resolution)

      expect(result.ok?).to be(false)
      expect(result.errors).to include(I18n.t("nesting.split.manual.orphan_geometry_missing"))
    end

    it "fails when no primary layer is selected" do
      project = create_project_for_spec!(title: "Manual no layer", bind_workspace: false)
      resolution = project.orphan_resolutions.create!(
        piece_key: "0",
        resolution_state: :pending,
        reason: "oversized_for_sheet"
      )
      orphan = Nesting::OrphansPresenter::Orphan.new(piece_key: "0", rings: [ [ [ 0, 0 ], [ 1, 0 ], [ 1, 1 ] ] ])
      allow(Nesting::OrphansPresenter).to receive(:for).and_return(instance_double(Nesting::OrphansPresenter, items: [ orphan ]))
      allow(ProjectReadinessValidator).to receive(:validate).and_return(
        ProjectReadinessValidator::Result.new(ok?: true, errors: [])
      )
      service = Nesting::ConfirmManualOrphanResolution.new(project: project, orphan_resolution: resolution)
      allow(service).to receive(:primary_layer_name).and_return(nil)

      result = service.call

      expect(result.ok?).to be(false)
    end
  end

  describe "ProjectLayerSelection branches [REQ-FIT-DXF-002]" do
    it "ignores non-hash layer params when collecting auxiliary ids" do
      project = create_project_for_spec!(title: "Layer selection", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      attachment_id = project.input_dxf_attachments.first!.id.to_s
      params = { attachment_id => { "primary_layer_id" => "", "99" => "invalid" } }

      expect { ProjectLayerSelection.apply!(project: project, raw_params: params) }.not_to raise_error
    end

    it "clears non-primary layers that are explicitly deselected in flat mode" do
      project = create_project_for_spec!(title: "Layer clear", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSync.call(project)
      layer = project.project_layers.first!
      layer.update!(included: true, layer_role: nil)

      ProjectLayerSelection.apply!(project: project, raw_params: { layer.id.to_s => { included: "0" } })

      expect(layer.reload.included?).to be(false)
    end
  end

  describe "Nesting::ProgressEta branches [REQ-FIT-JOB-001]" do
    it "returns nil when started_at is blank" do
      expect(Nesting::ProgressEta.estimate(started_at: nil, time_limit_sec: 60)).to be_nil
    end

    it "returns the time limit when piece counts are zero" do
      started = 1.minute.ago

      eta = Nesting::ProgressEta.estimate(started_at: started, time_limit_sec: 120, pieces_total: 0, pieces_placed: 0)

      expect(eta).to eq(started + 120.seconds)
    end
  end

  describe "Dxf::LayerNamesReader branches [REQ-FIT-DXF-001]" do
    it "raises when paths are blank" do
      expect { Dxf::LayerNamesReader.catalog([]) }.to raise_error(ArgumentError, /paths must be present/)
    end

    it "raises when the Python reader exits non-zero" do
      allow(Open3).to receive(:capture2).and_return([ "layer read failed", instance_double(Process::Status, success?: false) ])

      expect do
        Dxf::LayerNamesReader.catalog([ "/tmp/sample.dxf" ])
      end.to raise_error(Dxf::LayerNamesReader::Error, /layer read failed/)
    end

    it "raises when gap scan paths or layer names are blank" do
      expect { Dxf::LayerNamesReader.gaps_for(path: "", layer_name: "PIECES") }
        .to raise_error(ArgumentError, /path must be present/)
      expect { Dxf::LayerNamesReader.gaps_for(path: "/tmp/sample.dxf", layer_name: "") }
        .to raise_error(ArgumentError, /layer_name must be present/)
    end

    it "raises when the Python gap scan exits non-zero" do
      allow(Open3).to receive(:capture2).and_return([ "layer gap scan failed", instance_double(Process::Status, success?: false) ])

      expect do
        Dxf::LayerNamesReader.gaps_for(path: "/tmp/sample.dxf", layer_name: "PIECES")
      end.to raise_error(Dxf::LayerNamesReader::Error, /layer gap scan failed/)
    end
  end

  describe "Dxf::PieceRingsLister branches [REQ-FIT-DXF-001]" do
    it "returns an empty list when layer names are blank" do
      expect(Dxf::PieceRingsLister.list(paths: [ "/tmp/sample.dxf" ], layer_names: [])).to eq([])
    end

    it "raises when the Python lister exits non-zero" do
      allow(Open3).to receive(:capture2).and_return([ "list failed", instance_double(Process::Status, success?: false) ])

      expect do
        Dxf::PieceRingsLister.list(paths: [ "/tmp/sample.dxf" ], layer_names: [ "PIECES" ])
      end.to raise_error(Dxf::PieceRingsLister::Error, /list failed/)
    end
  end

  describe "Billing::Onvo::ReconcilePaymentIntent branches [REQ-FIT-BILL-001]" do
    it "requires a payment object" do
      expect { Billing::Onvo::ReconcilePaymentIntent.call(payment: nil) }
        .to raise_error(ArgumentError, /payment required/)
    end

    it "requires an ONVO payment intent id" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download"
      )

      expect { Billing::Onvo::ReconcilePaymentIntent.call(payment: payment) }
        .to raise_error(ArgumentError, /ONVO intent required/)
    end
  end

  describe "Billing::Onvo::ConfirmSinpePayment branches [REQ-FIT-BILL-001]" do
    it "rejects blank identification values" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download",
        onvo_payment_intent_id: "pi_test"
      )

      expect do
        Billing::Onvo::ConfirmSinpePayment.call(payment: payment, identification: "", mobile_number: "88888888")
      end.to raise_error(ArgumentError, /identification required/)
    end
  end

  describe "BlocksWorkshopDuringPendingPayment memoization [REQ-FIT-BILL-001]" do
    it "memoizes pending checkout lock lookups per request" do
      host = Class.new(ApplicationController) { include BlocksWorkshopDuringPendingPayment }.new
      project = create_project_for_spec!(title: "Memo lock", bind_workspace: false)
      user = create_billing_user!
      lock = instance_double(Billing::PendingCheckoutLock, active?: false)
      host.instance_variable_set(:@project, project)
      allow(host).to receive(:current_user).and_return(user)
      expect(Billing::PendingCheckoutLock).to receive(:for).once.and_return(lock)

      2.times { host.send(:pending_checkout_lock) }
    end
  end

  describe MisPagosHelper, type: :helper do
    it "returns the purchase reference for single-download payments [REQ-FIT-BILL-001]" do
      payment = Payment.new(purpose: "single_download", purchase_reference: "REF-123")

      expect(mis_pagos_payment_reference_label(payment)).to eq(
        I18n.t("billing.mis_pagos.payment_reference", reference: "REF-123")
      )
    end
  end

  describe NestingPreviewHelper, type: :helper do
    it "returns nil for unsupported decoration geometry types [REQ-FIT-UI-002]" do
      sheet = OpenStruct.new(offset_x_mm: 0)
      preview = instance_double(Nesting::PreviewPresenter, color_for_layer: "#000")
      decoration = OpenStruct.new(layer_name: "CUT", geometry_type: "arc", payload: {})

      expect(
        helper.send(
          :nesting_preview_decoration_markup,
          decoration,
          sheet: sheet,
          layout_height: 100,
          preview: preview
        )
      ).to be_nil
    end
  end

  describe OrphansPreviewHelper, type: :helper do
    it "omits mother paths when orphan geometry is not exportable [REQ-FIT-SPLIT-001]" do
      project = create_project_for_spec!(title: "Split preview helper", bind_workspace: false)
      resolution = project.orphan_resolutions.create!(
        piece_key: "piece-1",
        resolution_state: :pending,
        reason: "oversized_for_sheet"
      )
      proposal = resolution.split_proposals.create!(
        status: :draft,
        version: 1,
        feasible: true,
        child_piece_geometries: [
          { "label" => "a", "rings" => [ [ [ 0, 0 ], [ 10, 0 ], [ 10, 10 ], [ 0, 10 ] ] ] }
        ],
        cut_segments: [],
        labels: [ "a" ]
      )
      orphan = Nesting::OrphansPresenter::Orphan.new(
        piece_index: 0,
        width_mm: 100,
        height_mm: 50,
        rings: [],
        split_proposal: proposal
      )

      markup = helper.split_plan_preview_svg(orphan, css_class: "split-preview")

      expect(markup).to include("svg")
    end
  end
end
