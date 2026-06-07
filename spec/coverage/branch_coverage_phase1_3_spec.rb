# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Branch coverage quick wins (phases 1–3)" do
  include BillingModelHelpers
  include Rails.application.routes.url_helpers

  # --- Phase 1: services & models (1 missed branch) ---

  describe "Billing::FailPayment idempotency [REQ-FIT-BILL-001]" do
    it "returns :already_terminal when payment is already failed" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "failed",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download"
      )

      expect(Billing::FailPayment.call(payment: payment)).to eq(:already_terminal)
    end
  end

  describe "Analytics::TrackEvent payload guards [REQ-FIT-ANALYTICS-001]" do
    it "raises when call_payload receives a non-EventPayload" do
      expect { Analytics::TrackEvent.call_payload("not-a-payload") }
        .to raise_error(ArgumentError, /payload required/)
    end

    it "does not rate-limit when neither user_id nor anonymous_session_key is present" do
      expect(Analytics::TrackEvent.send(:rate_limit_exceeded?, nil, nil)).to be(false)
    end
  end

  describe "Billing::DownloadToken persistence guard [REQ-FIT-BILL-003]" do
    it "rejects unpersisted records at issue time" do
      user = User.new(email: "new@example.com", password: "securepassword12")
      run = NestingRun.new(status: "completed")

      expect { Billing::DownloadToken.issue(user: user, nesting_run: run) }
        .to raise_error(ArgumentError, /must be persisted/)
    end
  end

  describe "Dxf::OrphanPieceExporter failure path [REQ-FIT-NEST-003]" do
    it "raises when the Python exporter exits non-zero" do
      allow(Open3).to receive(:capture2).and_return([ "export failed", instance_double(Process::Status, success?: false) ])

      expect do
        Dxf::OrphanPieceExporter.export(rings: [ [ [ 0, 0 ], [ 1, 0 ], [ 1, 1 ] ] ] )
      end.to raise_error(Dxf::OrphanPieceExporter::Error, /export failed/)
    end
  end

  describe "SheetStocks::InvalidateNestingOutputs [REQ-FIT-NEST-004]" do
    it "returns false when the project has no nested outputs attached" do
      project = create_project_for_spec!(title: "No outputs", bind_workspace: false)

      expect(SheetStocks::InvalidateNestingOutputs.call(project)).to be(false)
    end
  end

  describe "Billing::CountryCode.from_geo_defaults [REQ-FIT-BILL-001]" do
    it "requires a geo hash" do
      expect { Billing::CountryCode.from_geo_defaults(nil) }
        .to raise_error(ArgumentError, /geo_hash required/)
    end
  end

  describe "Billing::Currency#compatible_with_payment_method? [REQ-FIT-BILL-001]" do
    it "accepts PaymentMethod value objects without re-parsing" do
      currency = Billing::Currency.parse(:crc)
      method = Billing::PaymentMethod.parse("sinpe_crc")

      expect(currency.compatible_with_payment_method?(method)).to be(true)
    end
  end

  describe "Billing::ProductKind pairing validation [REQ-FIT-BILL-001]" do
    it "rejects carts that specify both nesting_run and tier_months" do
      kind = Billing::ProductKind.parse("single_download")

      expect { kind.validate_pairing!(nesting_run: 1, tier_months: 1) }
        .to raise_error(ArgumentError, /invalid product pairing/)
    end
  end

  describe "DownloadGrant#purge_retained_blob! [REQ-FIT-BILL-003]" do
    it "no-ops when no retained blob is attached" do
      grant = DownloadGrant.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        kind: "single_purchase",
        retained_until: 1.day.from_now
      )

      expect { grant.purge_retained_blob! }.not_to raise_error
      expect(grant.retained_nested_dxf).not_to be_attached
    end
  end

  describe "Payment#incomplete_card_checkout_attempt? [REQ-FIT-BILL-001]" do
    it "returns false for succeeded card payments" do
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

      expect(payment.incomplete_card_checkout_attempt?).to be(false)
    end
  end

  describe "Billing::CartUpsert guest lookup [REQ-FIT-BILL-001]" do
    it "replaces an existing guest cart" do
      token = SecureRandom.hex(16)
      Cart.create!(
        guest_token: token,
        kind: "plan",
        tier_months: 1,
        currency_mode: "crc",
        list_price_cents: 3250,
        sinpe_price_cents: 3000
      )

      cart = Billing::CartUpsert.call(
        user: nil,
        guest_token: token,
        kind: "plan",
        tier_months: 2,
        currency_mode: "crc"
      )

      expect(cart.tier_months).to eq(2)
      expect(Cart.where(guest_token: token).count).to eq(1)
    end
  end

  describe "Billing::Onvo::ApiError i18n mapping [REQ-FIT-BILL-001]" do
    it "maps known API error codes to catalog keys" do
      error = Billing::Onvo::ApiError.new(
        "bad card",
        status: 422,
        body: { "code" => "cards.invalid_card_info" }
      )

      expect(error.user_message).to eq(I18n.t("billing.checkout.onvo.api_errors.invalid_card_info"))
    end
  end

  describe "Billing::Onvo::Config validation [REQ-FIT-BILL-001]" do
    it "rejects blank secret keys" do
      expect do
        Billing::Onvo::Config.new(
          secret_key: "  ",
          publishable_key: "pub",
          mode: "test",
          webhook_secret: "whsec"
        )
      end.to raise_error(ArgumentError, /secret_key required/)
    end
  end

  describe "Billing::Onvo::CreatePaymentIntent guards [REQ-FIT-BILL-001]" do
    it "rejects unpersisted payments" do
      payment = Payment.new(
        user: create_billing_user!,
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download"
      )
      breakdown = Billing::CheckoutBreakdown.for_single_download(
        billing_context: { currency: :usd, payment_method: :card, iva_applicable: false },
        overage: false
      )

      expect do
        Billing::Onvo::CreatePaymentIntent.call(payment: payment, breakdown: breakdown)
      end.to raise_error(ArgumentError, /must be persisted/)
    end
  end

  describe "Billing::Onvo::HandleWebhookEvent dispatch [REQ-FIT-BILL-001]" do
    it "ignores unsupported webhook event types" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download",
        onvo_payment_intent_id: "pi_ignored_event"
      )
      payload = {
        "type" => "payment-intent.created",
        "data" => { "id" => payment.onvo_payment_intent_id }
      }

      expect(Billing::Onvo::HandleWebhookEvent.call(payload: payload)).to eq(:ignored)
    end
  end

  describe "Billing::Onvo::HttpTransport [REQ-FIT-BILL-001]" do
    it "requires a config object" do
      expect { Billing::Onvo::HttpTransport.new(config: nil) }
        .to raise_error(ArgumentError, /config required/)
    end
  end

  describe "Billing::Onvo::SinpeInput test-mode guard [REQ-FIT-BILL-001]" do
    around do |example|
      previous_gateway = ENV["BILLING_GATEWAY"]
      previous_mode = ENV["ONVO_MODE"]
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_MODE"] = "test"
      example.run
    ensure
      ENV["BILLING_GATEWAY"] = previous_gateway
      ENV["ONVO_MODE"] = previous_mode
    end

    it "rejects non-test mobile numbers in ONVO test mode" do
      expect do
        Billing::Onvo::SinpeInput.parse!(
          identification: "112345678",
          mobile_number: "70123456"
        )
      end.to raise_error(ArgumentError, /sinpe_mobile_number_test_only/)
    end
  end

  describe "Billing::Onvo::TestSinpeMobileNumbers [REQ-FIT-BILL-001]" do
    it "normalizes numbers longer than eight digits to the last eight" do
      expect(Billing::Onvo::TestSinpeMobileNumbers.normalize_local("50688888888")).to eq("88888888")
    end
  end

  describe "Billing::Onvo::VerifyWebhook [REQ-FIT-BILL-001]" do
    it "returns false when the secret header is blank" do
      request = ActionDispatch::TestRequest.create
      config = Billing::Onvo::Config.new(
        secret_key: "secret",
        publishable_key: "pub",
        mode: "test",
        webhook_secret: "whsec"
      )

      expect(Billing::Onvo::VerifyWebhook.call(request: request, config: config)).to be(false)
    end
  end

  describe "Billing::Onvo::WebhookEvent [REQ-FIT-BILL-001]" do
    it "requires a payload" do
      expect { Billing::Onvo::WebhookEvent.new(nil) }
        .to raise_error(ArgumentError, /payload required/)
    end
  end

  describe "Billing::PendingCart validation [REQ-FIT-BILL-001]" do
    it "requires tier_months for plan carts" do
      expect do
        Billing::PendingCart.new(
          "kind" => "plan",
          "currency_mode" => "crc"
        )
      end.to raise_error(ArgumentError, /tier_months required/)
    end
  end

  describe "Billing::RecordPlanDownload token bypass [REQ-FIT-BILL-002]" do
    it "skips quota consumption when via_download_token is true" do
      user = create_billing_user!
      run = create_nesting_run!
      create_active_subscription!(user: user)

      expect(Billing::QuotaCounter).not_to receive(:for)

      Billing::RecordPlanDownload.call(
        user: user,
        nesting_run: run,
        via_download_token: true
      )
    end
  end

  describe "Billing::RegionalPolicy.normalize_country [REQ-FIT-BILL-001]" do
    it "returns parsed country codes" do
      expect(Billing::RegionalPolicy.send(:normalize_country, "CR")).to eq("CR")
    end
  end

  describe "Billing::SimulatePlanPurchase suspended user [REQ-FIT-BILL-002]" do
    it "rejects suspended users" do
      user = create_billing_user!
      user.update!(suspended_at: Time.current)
      project = Project.create!(ephemeral: true, title: "Suspended", status: :draft)

      expect do
        Billing::SimulatePlanPurchase.call(
          user: user,
          tier_months: 1,
          payment_method: "card_crc",
          outcome: "success",
          project: project
        )
      end.to raise_error(ArgumentError, /user suspended/)
    end
  end

  describe "Nesting::ConfigBuilder layer mode [REQ-FIT-CLI-001]" do
    it "uses legacy input_dxf_paths when no per-file layers exist" do
      project = create_project_for_spec!(title: "Legacy layers", bind_workspace: false)
      work_dir = Rails.root.join("tmp/nesting-config-spec")
      FileUtils.mkdir_p(work_dir)
      input = work_dir.join("input.dxf")
      File.write(input, "stub")

      payload = Nesting::ConfigBuilder.build(
        project: project,
        work_dir: work_dir,
        input_paths: [ input ]
      )

      expect(payload).to include(:input_dxf_paths)
      expect(payload).not_to include(:input_files)
    ensure
      FileUtils.rm_rf(work_dir)
    end
  end

  describe "Nesting::MaterializeSplitProposal guard [REQ-FIT-SPLIT-001]" do
    it "rejects infeasible proposals" do
      project = create_project_for_spec!(title: "Split", bind_workspace: false)
      resolution = project.orphan_resolutions.create!(
        piece_key: "piece-1",
        resolution_state: :pending,
        reason: "oversized_for_sheet"
      )
      proposal = resolution.split_proposals.create!(
        status: :draft,
        version: 1,
        feasible: false,
        plan_reason: "split_not_feasible",
        child_piece_geometries: [],
        cut_segments: [],
        labels: []
      )

      expect do
        Nesting::MaterializeSplitProposal.call(
          project: project,
          orphan_resolution: resolution,
          proposal: proposal
        )
      end.to raise_error(ArgumentError, /infeasible/)
    end
  end

  describe "Nesting::ProgressSnapshot message_key [REQ-FIT-JOB-001]" do
    it "preserves explicit message_key values from progress.json" do
      snapshot = Nesting::ProgressSnapshot.from_hash(
        {
          "version" => 1,
          "phase_id" => "fill",
          "percent" => 10,
          "message_key" => "nesting.custom.message"
        },
        last_percent: 0
      )

      expect(snapshot.message_key).to eq("nesting.custom.message")
    end
  end

  describe "Nesting::StatusMapper.attach_nested_output? [REQ-FIT-NEST-003]" do
    it "returns false for non-terminal statuses" do
      expect(
        Nesting::StatusMapper.attach_nested_output?(terminal_status: "processing", work_dir: "/tmp")
      ).to be(false)
    end
  end

  describe "Analytics::NestTelemetryContext fallback [REQ-FIT-ANALYTICS-001]" do
    it "skips fallback lookup when finished_at is not after the primary anchor" do
      project = create_project_for_spec!(title: "Nest telemetry", bind_workspace: false)
      anchor = 1.hour.ago
      run = project.nesting_runs.create!(
        status: "completed",
        created_at: anchor,
        started_at: anchor,
        finished_at: anchor
      )

      context = Analytics::NestTelemetryContext.from(project: project, nesting_run: run)

      expect(context.user_id).to be_nil
    end
  end

  describe "Workshop::UxMode welcome variant [REQ-FIT-UI-003]" do
    it "uses the setup variant in workshop setup mode" do
      project = create_project_for_spec!(title: "Setup", status: :draft, bind_workspace: false)
      allow(project).to receive(:workshop_setup_mode?).and_return(true)

      expect(Workshop::UxMode.new(project).welcome_variant).to eq(:setup)
    end
  end

  describe "Nesting::SplitPlanJob missing resolution [REQ-FIT-SPLIT-001]" do
    it "no-ops when the orphan resolution no longer exists" do
      expect do
        Nesting::SplitPlanJob.perform_now(999_999)
      end.not_to raise_error
    end
  end

  describe "Admin::ExportForm150Xlsx soporte rows [REQ-FIT-ADMIN-001]" do
    it "handles payments without paid_at timestamps" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "succeeded",
        payment_method: "card_crc",
        currency: "crc",
        amount: 1000,
        subtotal: 1000,
        tax_amount: 130,
        total_amount: 1130,
        purpose: "single_download",
        paid_at: Time.current
      )
      payment.update_column(:paid_at, nil)

      row = Admin::ExportForm150Xlsx.send(:soporte_row_values, payment)

      expect(row.first).to be_nil
    end
  end

  # --- Phase 2: controllers, concerns, helpers (1 missed branch) ---

  describe "ApplicationController#after_sign_in_path_for [REQ-FIT-AUTH-002]" do
    it "skips cart merge for non-User resources" do
      controller = ApplicationController.new
      controller.request = ActionDispatch::TestRequest.create
      allow(controller).to receive(:session).and_return({})
      allow(controller).to receive(:consume_workspace_return_to).and_return("/")
      expect(Billing::CartMergeOnLogin).not_to receive(:call)

      expect(controller.after_sign_in_path_for(:admin)).to eq("/")
    end
  end

  describe "RequiresBillingConfirmation [REQ-FIT-AUTH-002]" do
    it "redirects unconfirmed users away from checkout" do
      host = Class.new(ApplicationController) { include RequiresBillingConfirmation }.new
      user = create_billing_user!
      user.update!(confirmed_at: nil)
      host.request = ActionDispatch::TestRequest.create
      host.response = ActionDispatch::TestResponse.new
      allow(host).to receive(:current_user).and_return(user)
      allow(host).to receive(:redirect_to)

      host.send(:require_confirmed_for_checkout!)

      expect(host).to have_received(:redirect_to).with(
        email_confirmation_pending_path,
        alert: I18n.t("devise.failure.unconfirmed")
      )
    end
  end

  describe "RequiresNestedDownloadAuthorization [REQ-FIT-BILL-001]" do
    it "redirects when no downloadable nesting run exists" do
      host = Class.new(ApplicationController) { include RequiresNestedDownloadAuthorization }.new
      project = create_project_for_spec!(title: "No run", bind_workspace: false)
      project.nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
      host.request = ActionDispatch::TestRequest.create
      host.response = ActionDispatch::TestResponse.new
      host.instance_variable_set(:@project, project)
      allow(host).to receive(:redirect_to)
      allow(host).to receive(:current_user).and_return(create_billing_user!)

      host.send(:authorize_nested_download!)

      expect(host).to have_received(:redirect_to).with(
        workshop_path,
        alert: I18n.t("projects.show.nested_dxf_unavailable")
      )
    end
  end

  describe "BillingHelper#l_in_user_zone [REQ-FIT-BILL-002]" do
    let(:helper) { Class.new { include BillingHelper }.new }

    it "falls back to the default zone when user is nil" do
      time = Time.zone.parse("2026-01-15 12:00:00 UTC")

      label = helper.l_in_user_zone(time, format: :short, user: nil)

      expect(label).to be_present
      expect(label).not_to eq("")
    end
  end

  describe "MisPagosHelper payment reference [REQ-FIT-BILL-001]" do
    include MisPagosHelper

    it "returns nil for non-single-download payments" do
      payment = Payment.new(purpose: "plan_subscription", purchase_reference: "REF-1")

      expect(mis_pagos_payment_reference_label(payment)).to be_nil
    end
  end

  describe "Webhooks::OnvoController signature guard [REQ-FIT-BILL-001]", type: :request do
    it "returns unauthorized when the webhook secret does not match" do
      post "/webhooks/onvo",
           params: { type: "payment-intent.succeeded", data: { id: "pi_x" } }.to_json,
           headers: { "CONTENT_TYPE" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "Users::SessionsController logout confirmation [REQ-FIT-AUTH-002]" do
    it "renders confirmation when an active workspace exists" do
      controller = Users::SessionsController.new
      controller.request = ActionDispatch::TestRequest.create
      controller.response = ActionDispatch::TestResponse.new
      session_hash = {}
      project = Project.create!(ephemeral: true, title: "Active", status: :draft)
      Workspace.bind!(session_hash, project)
      allow(controller).to receive(:session).and_return(session_hash)
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new({}))
      allow(controller).to receive(:render)

      controller.destroy

      expect(controller).to have_received(:render).with(:confirm_destroy, status: :ok)
    end
  end

  # --- Phase 3: 2–3 missed branches (selected high-value files) ---

  describe "Billing::FulfillPayment guards [REQ-FIT-BILL-001]" do
    it "returns :already_fulfilled for succeeded payments" do
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

      expect(Billing::FulfillPayment.call(payment: payment)).to eq(:already_fulfilled)
    end

    it "requires a payment object" do
      expect { Billing::FulfillPayment.call(payment: nil) }
        .to raise_error(ArgumentError, /payment required/)
    end
  end

  describe "BlocksWorkshopDuringPendingPayment turbo response [REQ-FIT-BILL-001]" do
    it "renders turbo stream for locked sheet mutations" do
      host = Class.new(ProjectsController) do
        def render_workspace_turbo_stream(section, status: :ok)
          @rendered_section = section
          @rendered_status = status
        end
      end.new
      project = create_project_for_spec!(title: "Locked", bind_workspace: false)
      user = create_billing_user!
      lock = instance_double(
        Billing::PendingCheckoutLock,
        active?: true,
        message: "locked"
      )
      host.request = ActionDispatch::TestRequest.create
      host.request.headers["Accept"] = "text/vnd.turbo-stream.html"
      host.params = ActionController::Parameters.new(section: "layers")
      host.instance_variable_set(:@project, project)
      allow(host).to receive(:current_user).and_return(user)
      allow(Billing::PendingCheckoutLock).to receive(:for).and_return(lock)

      expect(host.send(:reject_workshop_mutation_if_pending_payment!)).to be(true)
      expect(host.instance_variable_get(:@rendered_section)).to eq(:layers)
      expect(host.instance_variable_get(:@rendered_status)).to eq(:unprocessable_content)
    end
  end

  describe "Analytics::Thresholds missing config [REQ-FIT-ANALYTICS-001]" do
    after do
      Analytics::Thresholds.send(:remove_instance_variable, :@config) if Analytics::Thresholds.instance_variable_defined?(:@config)
      Analytics::Thresholds.send(:remove_instance_variable, :@last_mtime) if Analytics::Thresholds.instance_variable_defined?(:@last_mtime)
    end

    it "loads defaults when analytics.yml is absent" do
      missing = Rails.root.join("tmp/missing-analytics-thresholds-branch-spec.yml")
      stub_const("Analytics::Thresholds::CONFIG_PATH", missing)

      expect(Analytics::Thresholds.low_priority_events_per_hour).to eq(300)
    end
  end

  describe "Billing::GeoPaymentDefaults country override [REQ-FIT-BILL-001]" do
    it "reads FITLOOP_BILLING_COUNTRY_OVERRIDE when set" do
      previous = ENV["FITLOOP_BILLING_COUNTRY_OVERRIDE"]
      ENV["FITLOOP_BILLING_COUNTRY_OVERRIDE"] = " us "
      request = ActionDispatch::TestRequest.create

      expect(Billing::GeoPaymentDefaults.country_override).to eq("US")
    ensure
      if previous.nil?
        ENV.delete("FITLOOP_BILLING_COUNTRY_OVERRIDE")
      else
        ENV["FITLOOP_BILLING_COUNTRY_OVERRIDE"] = previous
      end
    end
  end

  describe "Billing::ReleasePendingCheckoutLock [REQ-FIT-BILL-001]" do
    it "rejects payments that do not belong to the caller" do
      owner = create_billing_user!(email: "owner@example.com")
      other = create_billing_user!(email: "other@example.com")
      payment = Payment.create!(
        user: owner,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        total_amount: 1130,
        purpose: "single_download"
      )

      expect do
        Billing::ReleasePendingCheckoutLock.call(payment: payment, user: other)
      end.to raise_error(ArgumentError, /payment does not belong to user/)
    end
  end

  describe "Nesting::FailRun [REQ-FIT-JOB-001]" do
    it "returns early when the run is already terminal" do
      project = create_project_for_spec!(title: "Terminal", bind_workspace: false)
      run = project.nesting_runs.create!(status: "failed")

      expect(Nesting::FailRun.call(nesting_run: run)).to be(false)
      expect(run.reload.status).to eq("failed")
    end
  end

  describe "PersistWorkspaceLayerSelectionDraft [REQ-FIT-UI-005]" do
    it "returns false when params contain no layer selection" do
      service = PersistWorkspaceLayerSelectionDraft.new(session: {}, params: {})

      expect(service.send(:selection_in_params?, {})).to be(false)
    end
  end
end
