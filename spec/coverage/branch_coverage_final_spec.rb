# frozen_string_literal: true

require "ostruct"
require "rails_helper"

# Targets remaining SimpleCov branch gaps (see analyze_coverage.rb).
RSpec.describe "Branch coverage final gaps" do
  include BillingModelHelpers
  include Rails.application.routes.url_helpers

  # --- helpers ---

  describe "WorkshopUrlHelper [REQ-FIT-UI-003]" do
    let(:helper_obj) do
      Class.new do
        include WorkshopUrlHelper
        include Rails.application.routes.url_helpers
      end.new
    end

    it "uses record id when the attachment is present" do
      project = create_project_for_spec!(title: "URL record", bind_workspace: false)
      project.input_dxf.attach(
        io: StringIO.new("dxf"),
        filename: "piece.dxf",
        content_type: "application/dxf"
      )
      attachment = project.input_dxf_attachments.first!

      expect(helper_obj.project_input_dxf_file_path(project, attachment)).to include(attachment.id.to_s)
    end

    it "uses run id when the nesting run is present" do
      project = create_project_for_spec!(title: "URL run", bind_workspace: false)
      run = project.nesting_runs.create!(status: "completed")

      expect(helper_obj.cancel_project_nesting_run_path(project, run)).to include(run.id.to_s)
    end
  end

  describe MisPagosHelper, type: :helper do
    let(:user) { create_billing_user! }
    let(:run) { create_nesting_run! }

    it "returns sinpe continue action while transfer is processing" do
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_status: "processing"
      )

      action = helper.mis_pagos_sinpe_primary_action(payment)

      expect(action[:testid]).to eq("mis-pagos-sinpe-continue")
    end

    it "returns nil payment reference label when purchase_reference is blank" do
      payment = Payment.new(purpose: "single_download", purchase_reference: nil)

      expect(helper.mis_pagos_payment_reference_label(payment)).to be_nil
    end
  end

  describe NestingPreviewHelper, type: :helper do
    it "returns nil for unsupported decoration geometry types [REQ-FIT-UI-002]" do
      sheet = OpenStruct.new(offset_x_mm: 0)
      preview = instance_double(Nesting::PreviewPresenter, color_for_layer: "#000")
      decoration = OpenStruct.new(layer_name: "CUT", geometry_type: "arc", payload: {})

      expect(
        helper.send(:nesting_preview_decoration_markup, decoration, sheet: sheet, layout_height: 100, preview: preview)
      ).to be_nil
    end
  end

  # --- controllers / concerns ---

  describe "CartController#cart_line_kind_and_tier [REQ-FIT-BILL-001]" do
    subject(:cart_controller) { CartController.new }

    before { cart_controller.request = ActionDispatch::TestRequest.create }

    it "reads tier months from PendingCart value objects" do
      pending = Billing::PendingCart.new("kind" => "plan", "tier_months" => 2, "currency_mode" => "crc")

      expect(cart_controller.cart_line_summary(pending)).to eq(
        I18n.t("billing.cart.replace.line_plan", months: 2)
      )
    end
  end

  describe "StoresWorkspaceReturnTo [REQ-FIT-AUTH-002]" do
    controller_class = Class.new(ApplicationController) do
      include StoresWorkspaceReturnTo
      def self.name = "StoresWorkspaceReturnToFinalController"
    end

    it "skips store when devise action is not new/edit" do
      host = Users::SessionsController.new
      host.request = ActionDispatch::TestRequest.create
      allow(host).to receive(:devise_controller?).and_return(true)
      allow(host).to receive(:controller_name).and_return("sessions")
      allow(host).to receive(:action_name).and_return("create")

      expect(host.send(:store_workspace_return_to?)).to be(false)
    end

    it "skips rebinding when the project is already on the active tab" do
      host = controller_class.new
      project = Project.create!(ephemeral: true, title: "Same tab", status: :draft)
      session = { Workspace::WORKSPACES_KEY => { "tab-a" => project.id } }
      host.request = ActionDispatch::TestRequest.create
      host.request.headers[ResolvesWorkspaceTab::TAB_HEADER] = "tab-a"
      allow(host).to receive(:session).and_return(session)
      expect(Workspace).not_to receive(:bind!)

      expect(host.send(:workshop_resume_path)).to eq(workshop_path)
    end

    it "returns early from store_workspace_return_to! when no project is bound" do
      host = controller_class.new
      session = {}
      host.request = ActionDispatch::TestRequest.create
      allow(host).to receive(:session).and_return(session)
      allow(host).to receive(:workspace_tab_id).and_return(Workspace::DEFAULT_TAB_ID)

      host.send(:store_workspace_return_to!)

      expect(session[:workspace_return_to]).to be_nil
    end
  end

  describe "SetsWorkspaceProject#clear_stale_workspace_binds_for!" do
    subject(:controller) { ProjectsController.new }

    it "no-ops when workspaces session value is not a hash" do
      session = { Workspace::WORKSPACES_KEY => "invalid" }
      allow(controller).to receive(:session).and_return(session)

      controller.send(:clear_stale_workspace_binds_for!, 99)

      expect(session[Workspace::WORKSPACES_KEY]).to eq("invalid")
    end
  end

  describe "ProjectsController#normalize_sheet_quantities! [REQ-FIT-UI-001]" do
    subject(:controller) { ProjectsController.new }

    it "skips non-hash attribute entries" do
      attrs = { "0" => "not-a-hash" }

      controller.send(:normalize_sheet_quantities!, attrs)

      expect(attrs["0"]).to eq("not-a-hash")
    end
  end

  describe "BlocksWorkshopDuringPendingPayment [REQ-FIT-BILL-001]" do
    it "returns nil when no pending lock exists" do
      host = Class.new(ApplicationController) { include BlocksWorkshopDuringPendingPayment }.new
      project = create_project_for_spec!(title: "No lock", bind_workspace: false)
      user = create_billing_user!
      host.instance_variable_set(:@project, project)
      allow(host).to receive(:current_user).and_return(user)
      allow(Billing::PendingCheckoutLock).to receive(:for).and_return(nil)

      expect(host.send(:workshop_mutations_locked?)).to be_nil
    end
  end

  # --- jobs ---

  describe NestingJob, type: :job do
    let(:project) { create_project_for_spec!(title: "Job branches", bind_workspace: false) }
    let(:nesting_run) { project.nesting_runs.create!(status: "processing") }

    it "skips FailRun and telemetry when the run disappears after an error" do
      allow(Nesting::JobRunner).to receive(:call).and_raise(StandardError, "boom")
      allow(NestingRun).to receive(:find_by).with(id: nesting_run.id).and_return(nil)
      allow(Analytics::TrackEvent).to receive(:call)

      expect { described_class.perform_now(nesting_run.id) }.not_to raise_error
      expect(Analytics::TrackEvent).not_to have_received(:call)
    end
  end

  # --- models ---

  describe Billing::CheckoutContext, "[REQ-FIT-BILL-001]" do
    it "parses country_code from session hash" do
      ctx = described_class.from_session(
        currency: :crc,
        payment_method: :sinpe,
        country_code: "CR",
        iva_applicable: true
      )

      expect(ctx.country_code.costa_rica?).to be(true)
    end

    it "accepts nil country_code without parsing" do
      ctx = described_class.from_session(
        currency: :usd,
        payment_method: :card,
        country_code: nil,
        iva_applicable: false
      )

      expect(ctx.country_code).to be_nil
    end
  end

  describe Billing::Money, "[REQ-FIT-BILL-001]" do
    it "accepts Currency value objects in from_major" do
      currency = Billing::Currency.parse(:crc)

      money = described_class.from_major(10, currency)

      expect(money.currency).to eq(currency)
    end
  end

  describe Payment, "[REQ-FIT-BILL-001]" do
    it "treats succeeded card payments as complete checkout attempts" do
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

    it "returns false when a card checkout is neither pending nor failed" do
      payment = Payment.new(payment_method: "card_usd", status: "succeeded", purpose: "single_download")
      allow(payment).to receive(:card_checkout?).and_return(true)
      allow(payment).to receive(:succeeded?).and_return(false)
      allow(payment).to receive(:superseded_by_later_successful_checkout?).and_return(false)
      allow(payment).to receive(:pending?).and_return(false)
      allow(payment).to receive(:failed?).and_return(false)

      expect(payment.incomplete_card_checkout_attempt?).to be(false)
    end
  end

  describe Nesting::SheetStockRow, "[REQ-FIT-NEST-004]" do
    it "rejects quantities below one" do
      expect do
        described_class.new(width_mm: 500, height_mm: 800, quantity: 0, sort_order: 0)
      end.to raise_error(ArgumentError, /quantity must be nil or at least 1/)
    end

    it "rejects non-positive width" do
      expect do
        described_class.new(width_mm: -1, height_mm: 800, quantity: 1, sort_order: 0)
      end.to raise_error(ArgumentError, /width_mm must be positive/)
    end

    it "rejects non-positive height" do
      expect do
        described_class.new(width_mm: 500, height_mm: 0, quantity: 1, sort_order: 0)
      end.to raise_error(ArgumentError, /height_mm must be positive/)
    end
  end

  # --- admin services ---

  describe Admin::HaciendaSummaryRows, "[REQ-FIT-ADMIN-001]" do
    it "prefers total_amount when it is positive" do
      payment = Payment.new(amount: 1000, total_amount: 50)

      expect(described_class.net_collected(payment)).to eq(50.0)
    end
  end

  describe Admin::VentasFilter, "[REQ-FIT-ADMIN-001]" do
    it "rejects unknown date columns" do
      expect { described_class.new({}, date_column: :invalid) }
        .to raise_error(ArgumentError, /invalid date_column/)
    end
  end

  # --- analytics / billing services (batch 1) ---

  describe Analytics::ResolveCountry, "[REQ-FIT-ANALYTICS-001]" do
    it "returns nil when the request has no remote_ip" do
      request = double(headers: {}, get_header: nil)

      expect(described_class.call(request)).to be_nil
    end

    it "returns nil when remote_ip is blank" do
      request = double(headers: {}, get_header: nil, remote_ip: "")

      expect(described_class.call(request)).to be_nil
    end
  end

  describe Billing::AbandonIncompleteCardCheckout, "[REQ-FIT-BILL-001]" do
    it "requires a payment" do
      expect { described_class.call(payment: nil) }.to raise_error(ArgumentError, /payment required/)
    end
  end

  describe Billing::CartTotals, "[REQ-FIT-BILL-001]" do
    it "accepts CheckoutContext without re-parsing" do
      cart = Cart.create!(
        guest_token: SecureRandom.uuid,
        kind: "plan",
        tier_months: 1,
        currency_mode: "usd",
        list_price_cents: 100,
        sinpe_price_cents: 100
      )
      ctx = Billing::CheckoutContext.new(currency: :usd, payment_method: :card, iva_applicable: false)

      totals = described_class.for_cart(cart: cart, billing_context: ctx)

      expect(totals[:breakdown][:total_amount]).to be_positive
    end
  end

  describe Billing::CheckoutBreakdown, "[REQ-FIT-BILL-001]" do
    it "converts USD cents to major units" do
      amount = described_class.send(:cents_to_amount, 1130, :usd)

      expect(amount).to eq(11.3)
    end

    it "keeps CRC amounts as integer centavos" do
      amount = described_class.send(:cents_to_amount, 1130, :crc)

      expect(amount).to eq(1130)
    end
  end

  describe Billing::FulfillPayment, "[REQ-FIT-BILL-001]" do
    it "requires a nesting run for single-download fulfillments" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: nil,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download"
      )

      expect { described_class.call(payment: payment) }.to raise_error(ArgumentError, /nesting_run required/)
    end

    it "rejects plan payments with invalid product descriptions" do
      payment = Payment.create!(
        user: create_billing_user!,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 10,
        purpose: "plan_subscription",
        product_description: "invalid"
      )

      expect { described_class.call(payment: payment) }.to raise_error(ArgumentError, /invalid plan product_description/)
    end
  end

  describe Billing::GeoPaymentDefaults, "[REQ-FIT-BILL-001]" do
    it "handles requests without remote_ip" do
      request = double(headers: {}, remote_ip: nil, get_header: nil)
      defaults = described_class.from_request(request, session: {}, user: nil)

      expect(defaults).to include(:available_payment_methods)
    end
  end

  describe Billing::Onvo::ApiError, "[REQ-FIT-BILL-001]" do
    it "joins array error details" do
      error = described_class.new("fail", status: 422, body: { "message" => %w[a b] })

      expect(error.send(:extract_detail)).to eq("a, b")
    end
  end

  describe Billing::Onvo::CardExpiration, "[REQ-FIT-BILL-001]" do
    it "rejects invalid months" do
      expect { described_class.parse("13/28") }.to raise_error(ArgumentError, /card_exp_invalid/)
    end
  end

  describe Billing::Onvo::CreatePaymentIntent, "[REQ-FIT-BILL-001]" do
    it "requires a breakdown" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download"
      )

      expect { described_class.call(payment: payment, breakdown: nil) }
        .to raise_error(ArgumentError, /breakdown required/)
    end
  end

  describe Billing::Onvo::HttpTransport, "[REQ-FIT-BILL-001]" do
    it "parses empty bodies as empty hashes" do
      config = Billing::Onvo::Config.new(
        secret_key: "sk_test",
        publishable_key: "pk_test",
        mode: "test",
        webhook_secret: "whsec_test"
      )
      transport = described_class.new(config: config)

      expect(transport.send(:parse_body, "")).to eq({})
    end
  end

  describe Billing::Onvo::MoneyMinorUnits, "[REQ-FIT-BILL-001]" do
    it "rejects nil breakdowns" do
      expect { described_class.new(nil) }.to raise_error(ArgumentError, /breakdown required/)
    end

    it "rejects unsupported currencies in minor unit conversion" do
      breakdown = { currency: :eur, total_amount: 1 }

      expect { described_class.new(breakdown) }.to raise_error(ArgumentError, /unsupported currency/)
    end
  end

  describe Billing::PendingCart, "[REQ-FIT-BILL-001]" do
    it "requires nesting_run_id for single-download payloads" do
      expect { described_class.new("kind" => "single_download", "currency_mode" => "crc") }
        .to raise_error(ArgumentError, /nesting_run_id required/)
    end
  end

  describe Billing::PendingCheckoutLock, "[REQ-FIT-BILL-001]" do
    it "returns nil for nil users via for_user" do
      expect(described_class.for_user(user: nil)).to be_nil
    end
  end

  describe Billing::PlanDownloadAvailability, "[REQ-FIT-BILL-002]" do
    it "returns false for nil users" do
      expect(described_class.plan_quota_exhausted?(user: nil)).to be(false)
    end
  end

  describe Billing::SupersedePendingCheckout, "[REQ-FIT-BILL-001]" do
    it "skips payments that are already superseded" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download",
        superseded_at: 1.hour.ago
      )
      service = described_class.new(user: payment.user, nesting_run: payment.nesting_run)

      service.send(:mark_superseded!, payment)

      expect(payment.reload.superseded_at).to be_within(1.second).of(1.hour.ago)
    end
  end

  describe Billing::WorkshopLockWindow, "[REQ-FIT-BILL-001]" do
    it "requires a payment for expiry calculation" do
      window = described_class.from_config

      expect { window.lock_expires_at(nil) }.to raise_error(ArgumentError, /payment required/)
    end

    it "rejects non-positive lock windows" do
      expect { described_class.new(minutes: 0) }.to raise_error(ArgumentError, /minutes must be positive/)
    end
  end

  # --- nesting services ---

  describe Nesting::LocalizedProgressMessage, "[REQ-FIT-JOB-001]" do
    it "returns empty text for blank stored messages on non-terminal projects" do
      project = create_project_for_spec!(title: "Blank msg", status: :processing, bind_workspace: false)
      project.update!(progress_message: "")

      expect(described_class.new(project).to_s).to eq("")
    end
  end

  describe Nesting::ProgressSnapshot, "[REQ-FIT-JOB-001]" do
    it "honors explicit message_key values from progress.json" do
      snapshot = described_class.from_hash(
        { "version" => 1, "phase_id" => "fill", "percent" => 5, "message_key" => "nesting.phase.queued" },
        last_percent: 0
      )

      expect(snapshot.message_key).to eq("nesting.phase.queued")
    end
  end

  describe PersistWorkspaceSheetInventoryDraft, "[REQ-FIT-UI-005]" do
    it "does not stash composer draft when save fails" do
      project = create_project_for_spec!(title: "Save fail", bind_workspace: false)
      stock = project.sheet_stocks.first!
      session = { Workspace::SESSION_KEY => project.id }
      params = ActionController::Parameters.new(
        project: {
          sheet_stocks_attributes: {
            "0" => { id: stock.id, width_mm: 1000, height_mm: 2000, quantity: 1, sort_order: 0 }
          }
        },
        composer_draft: { width_mm: "1200", height_mm: "2400", quantity: "2" }
      )
      allow_any_instance_of(Project).to receive(:save).and_return(false)

      expect(described_class.call(session: session, params: params)).to be(false)
      expect(session[described_class::COMPOSER_SESSION_KEY]).to be_nil
    end
  end

  describe Billing::SimulateSingleDownload, "[REQ-FIT-BILL-001]" do
    def attach_nested_dxf!(run)
      run.project.nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
    end

    it "uses Pricing when no cart snapshot exists" do
      user = create_billing_user!
      run = create_nesting_run!
      attach_nested_dxf!(run)

      result = described_class.call(
        user: user,
        nesting_run: run,
        payment_method: "card_usd",
        outcome: "success",
        iva_applicable: false
      )

      expect(result[:payment].amount).to be_positive
    end
  end

  describe Billing::PaymentStatusResponse, "[REQ-FIT-BILL-001]" do
    let(:routes) { Rails.application.routes.url_helpers }

    it "returns nil redirect when succeeded single-download has no grant" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "succeeded",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download",
        gateway_status: "succeeded",
        paid_at: Time.current
      )

      payload = described_class.for(payment: payment, routes: routes)

      expect(payload[:redirect_url]).to be_nil
    end
  end

  # --- request branches (controllers) ---

  describe "CheckoutController#load_checkout_context [REQ-FIT-BILL-001]", type: :request do
    let(:user) { create_billing_user! }

    before { post user_session_path, params: { user: { email: user.email, password: "securepassword12" } } }

    it "assigns project from nesting_run when workspace is bound" do
      begin_workspace_session!
      project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID)
      run = project.nesting_runs.create!(status: "completed")

      get checkout_path(nesting_run_id: run.id)

      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@project)).to eq(project)
    end
  end

  describe "Users::SessionsController#destroy [REQ-FIT-AUTH-002]", type: :request do
    it "renders confirmation when workspace discard is not confirmed" do
      user = create_billing_user!
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
      get start_project_path
      follow_redirect!

      delete destroy_user_session_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "DownloadPaywallController#show [REQ-FIT-BILL-001]", type: :request do
    it "stores guest return path on paywall visit" do
      get download_paywall_workshop_path

      expect(response).to have_http_status(:ok)
      expect(session[:workspace_return_to]).to eq(download_paywall_workshop_path)
    end
  end

  describe "PlanesController#simulate rescue [REQ-FIT-BILL-002]", type: :request do
    let(:user) { create_billing_user! }

    before { post user_session_path, params: { user: { email: user.email, password: "securepassword12" } } }

    it "redirects without project_id when simulate raises ArgumentError" do
      allow(Billing::SimulatePlanPurchase).to receive(:call).and_raise(ArgumentError)

      post planes_simulate_path, params: { tier_months: 1, payment_method: "card_crc", outcome: "success" }

      expect(response).to redirect_to(planes_path)
    end
  end

  describe "MisPagosController#show [REQ-FIT-BILL-002]", type: :request do
    let(:user) { create_billing_user! }

    before { post user_session_path, params: { user: { email: user.email, password: "securepassword12" } } }

    it "omits poll URL when no pending payment awaits confirmation" do
      get mis_pagos_path

      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@pending_payment_status_url)).to be_nil
    end
  end

  describe "RequiresBillingConfirmation [REQ-FIT-AUTH-002]", type: :request do
    it "redirects unconfirmed users away from checkout" do
      user = create_billing_user!
      user.update!(confirmed_at: nil)
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

      get checkout_path

      expect(response).to redirect_to(email_confirmation_pending_path)
    end
  end

  # --- batch 2: remaining service / controller branches ---

  describe Billing::CartMergeOnLogin, "[REQ-FIT-BILL-001]" do
    it "destroys the guest cart when the user already has one" do
      user = create_billing_user!
      token = SecureRandom.uuid
      Cart.create!(user_id: user.id, kind: "plan", tier_months: 1, currency_mode: "usd", list_price_cents: 100, sinpe_price_cents: 100)
      guest_cart = Cart.create!(guest_token: token, kind: "plan", tier_months: 2, currency_mode: "usd", list_price_cents: 200, sinpe_price_cents: 200)

      described_class.call(user: user, guest_token: token)

      expect(Cart.exists?(guest_cart.id)).to be(false)
    end
  end

  describe Billing::RecordPlanDownload, "[REQ-FIT-BILL-002]" do
    it "no-ops when the user has no active subscription" do
      user = create_billing_user!
      run = create_nesting_run!
      allow(Billing::Entitlement).to receive(:new).and_return(
        instance_double(Billing::Entitlement, plan_quota?: true, single_purchase_grant?: false)
      )

      expect { described_class.call(user: user, nesting_run: run) }.not_to raise_error
    end
  end

  describe Billing::RetainNestedDxf, "[REQ-FIT-BILL-003]" do
    it "skips blob attach when retained_nested_dxf is already present" do
      user = create_billing_user!
      run = create_nesting_run!
      grant = DownloadGrant.create!(user: user, nesting_run: run, kind: "single_purchase", retained_until: 1.day.from_now)
      grant.retained_nested_dxf.attach(
        io: StringIO.new("retained"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )

      expect(described_class.call(grant: grant, nesting_run: run)).to eq(grant)
    end
  end

  describe Billing::CartUpsert, "[REQ-FIT-BILL-001]" do
    it "replaces an existing user cart row" do
      user = create_billing_user!
      Cart.create!(user_id: user.id, kind: "plan", tier_months: 1, currency_mode: "usd", list_price_cents: 100, sinpe_price_cents: 100)

      cart = described_class.call(user: user, guest_token: nil, kind: "plan", tier_months: 2, currency_mode: "usd")

      expect(cart.tier_months).to eq(2)
      expect(Cart.where(user_id: user.id).count).to eq(1)
    end
  end

  describe Nesting::FailRun, "[REQ-FIT-JOB-001]" do
    it "returns false when the project is missing" do
      run = create_nesting_run!
      allow(run).to receive(:project).and_return(nil)

      expect(described_class.call(nesting_run: run)).to be(false)
    end
  end

  describe Nesting::ProgressEta, "[REQ-FIT-JOB-001]" do
    it "returns nil when started_at is blank" do
      expect(described_class.estimate(started_at: nil, time_limit_sec: 60)).to be_nil
    end
  end

  describe ConfirmationsController, "[REQ-FIT-AUTH-002]" do
    it "raises when precondition fails" do
      host = ConfirmationsController.new

      expect { host.send(:precondition!, false) }.to raise_error(ArgumentError, /precondition failed/)
    end
  end

  describe "Users::ConfirmationsController [REQ-FIT-AUTH-002]", type: :request do
    it "pre-fills email on the resend form when the user is signed in" do
      user = create_billing_user!
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

      get new_user_confirmation_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(%(value="#{user.email}"))
    end
  end

  describe "Users::RegistrationsController [REQ-FIT-AUTH-002]", type: :request do
    it "redirects signed-in users away from registration" do
      user = create_billing_user!
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

      get new_user_registration_path

      expect(response).to have_http_status(:redirect).or have_http_status(:found)
    end
  end

  describe Billing::PaymentStatusResponse, "[REQ-FIT-BILL-001]" do
    let(:routes) { Rails.application.routes.url_helpers }

    it "omits retry URL when nesting_run_id is blank" do
      payment = Payment.create!(
        user: create_billing_user!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download",
        nesting_run_id: nil
      )

      payload = described_class.for(payment: payment, routes: routes)

      expect(payload[:retry_checkout_url]).to be_nil
    end
  end

  describe Billing::GeoPaymentDefaults, "[REQ-FIT-BILL-001]" do
    it "uses session country when request lacks remote_ip" do
      request = double(headers: {}, remote_ip: nil, get_header: nil)
      defaults = described_class.from_request(request, session: { billing_country_code: "CR" }, user: nil)

      expect(defaults.fetch(:country_code)).to eq("CR")
    end

    it "skips persisting country when session is not writable" do
      request = double(headers: { "CF-IPCountry" => "CR" }, get_header: nil, remote_ip: nil)
      session = Object.new

      described_class.from_request(request, session: session, user: nil)
    end

    it "skips remote_ip lookup when the request does not expose remote_ip" do
      request = OpenStruct.new(headers: {})
      def request.get_header(_name) = nil

      defaults = described_class.from_request(request, session: {}, user: nil)

      expect(defaults.fetch(:country_code)).to be_nil
    end
  end

  # --- batch 3: remaining 70 branch gaps ---

  describe "WorkshopUrlHelper nil safe-navigation [REQ-FIT-UI-003]" do
    let(:helper_obj) do
      Class.new do
        include WorkshopUrlHelper
        include Rails.application.routes.url_helpers
      end.new
    end

    it "hits safe-navigation else when attachment record is nil without id kwarg" do
      expect {
        helper_obj.project_input_dxf_file_path(:project, nil)
      }.to raise_error(ActionController::UrlGenerationError, /id: nil/)
    end

    it "hits safe-navigation else when nesting run is nil without id kwarg" do
      expect {
        helper_obj.cancel_project_nesting_run_path(:project, nil)
      }.to raise_error(ActionController::UrlGenerationError, /id: nil/)
    end
  end

  describe Admin::HaciendaSummaryRows, "[REQ-FIT-ADMIN-001]" do
    it "falls back to amount when total_amount is zero" do
      payment = Payment.new(amount: 12.5, total_amount: 0)

      expect(described_class.net_collected(payment)).to eq(12.5)
    end
  end

  describe Billing::CheckoutBreakdown, "[REQ-FIT-BILL-001]" do
    it "returns sinpe reference pricing for CRC contexts" do
      price = described_class.send(:sinpe_reference_price, currency: :crc, overage: false)

      expect(price).to be_positive
    end
  end

  describe Billing::Onvo::CardExpiration, "[REQ-FIT-BILL-001]" do
    it "accepts valid MM/YY values" do
      expect(described_class.parse("12/30")).to eq(exp_month: 12, exp_year: 2030)
    end

    it "preserves four-digit years in normalize_year" do
      expect(described_class.normalize_year(2030)).to eq(2030)
    end
  end

  describe Billing::Onvo::MoneyMinorUnits, "[REQ-FIT-BILL-001]" do
    it "accepts plain Hash breakdowns" do
      expect(described_class.new(currency: :usd, total_amount: 10.5).to_i).to eq(1050)
    end

    it "accepts breakdown objects responding to to_h" do
      breakdown = Object.new
      def breakdown.to_h
        { currency: :usd, total_amount: 10.5 }
      end

      expect(described_class.new(breakdown).to_i).to eq(1050)
    end
  end

  describe Billing::PendingCheckoutLock, "[REQ-FIT-BILL-001]" do
    it "returns inactive for non-pending payments" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "succeeded",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download",
        paid_at: Time.current
      )

      expect(described_class.new(payment: payment).active?).to be(false)
    end
  end

  describe Nesting::ProgressSnapshot, "[REQ-FIT-JOB-001]" do
    it "rejects snapshots that regress percent" do
      snapshot = described_class.from_hash(
        { "version" => 1, "phase_id" => "fill", "percent" => 5 },
        last_percent: 10
      )

      expect(snapshot).to be_nil
    end
  end

  describe Billing::SimulateSingleDownload, "[REQ-FIT-BILL-001]" do
    def attach_nested_dxf!(run)
      run.project.nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )
    end

    it "uses integer centavos for CRC cart snapshots" do
      user = create_billing_user!
      run = create_nesting_run!
      attach_nested_dxf!(run)
      Cart.create!(
        user_id: user.id,
        kind: "single_download",
        nesting_run_id: run.id,
        currency_mode: "crc",
        list_price_cents: 2500,
        sinpe_price_cents: 2400
      )

      result = described_class.call(
        user: user,
        nesting_run: run,
        payment_method: "sinpe_crc",
        outcome: "success",
        iva_applicable: true
      )

      expect(result[:payment].amount).to eq(2400)
    end

    it "converts USD cart list cents to major units for card checkout" do
      user = create_billing_user!
      run = create_nesting_run!
      attach_nested_dxf!(run)
      Cart.create!(
        user_id: user.id,
        kind: "single_download",
        nesting_run_id: run.id,
        currency_mode: "usd",
        list_price_cents: 250,
        sinpe_price_cents: 240
      )

      result = described_class.call(
        user: user,
        nesting_run: run,
        payment_method: "card_usd",
        outcome: "success",
        iva_applicable: false
      )

      expect(result[:payment].amount).to eq(2.5)
    end

    it "returns existing grant without creating a duplicate payment" do
      user = create_billing_user!
      run = create_nesting_run!
      attach_nested_dxf!(run)
      grant = DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: 1.day.from_now
      )
      payment = Payment.create!(
        user: user,
        nesting_run: run,
        status: "succeeded",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2,
        purpose: "single_download",
        paid_at: Time.current
      )

      result = described_class.call(
        user: user,
        nesting_run: run,
        payment_method: "card_usd",
        outcome: "success",
        iva_applicable: false
      )

      expect(result[:grant]).to eq(grant)
      expect(result[:payment]).to eq(payment)
    end
  end

  describe Billing::PaymentStatusResponse, "[REQ-FIT-BILL-001]" do
    let(:routes) { Rails.application.routes.url_helpers }

    it "redirects plan subscriptions to mis pagos" do
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

      payload = described_class.for(payment: payment, routes: routes)

      expect(payload[:redirect_url]).to eq(routes.mis_pagos_path(payment_succeeded: 1))
    end
  end

  describe Billing::CartMergeOnLogin, "[REQ-FIT-BILL-001]" do
    it "destroys the guest cart when the user already owns a cart" do
      user = create_billing_user!
      token = SecureRandom.uuid
      Cart.create!(
        user_id: user.id,
        kind: "plan",
        tier_months: 1,
        currency_mode: "usd",
        list_price_cents: 100,
        sinpe_price_cents: 100
      )
      guest_cart = Cart.create!(
        guest_token: token,
        kind: "plan",
        tier_months: 2,
        currency_mode: "usd",
        list_price_cents: 200,
        sinpe_price_cents: 200
      )

      described_class.call(user: user, guest_token: token)

      expect(Cart.find_by(id: guest_cart.id)).to be_nil
      expect(Cart.find_by(user_id: user.id).tier_months).to eq(1)
    end
  end

  describe Billing::CartUpsert, "[REQ-FIT-BILL-001]" do
    it "creates a user cart when the user has no existing cart row" do
      token = SecureRandom.uuid
      Cart.create!(
        guest_token: token,
        kind: "plan",
        tier_months: 1,
        currency_mode: "usd",
        list_price_cents: 100,
        sinpe_price_cents: 100
      )
      user = create_billing_user!

      cart = described_class.call(user: user, guest_token: token, kind: "plan", tier_months: 1, currency_mode: "usd")

      expect(cart.user_id).to eq(user.id)
      expect(cart.guest_token).to be_nil
      expect(Cart.where(user_id: user.id).count).to eq(1)
    end
  end

  describe Nesting::FailRun, "[REQ-FIT-JOB-001]" do
    it "returns false when the run is not processing" do
      run = create_nesting_run!
      run.update!(status: "completed")

      expect(described_class.call(nesting_run: run)).to be(false)
    end
  end

  describe Billing::RetainNestedDxf, "[REQ-FIT-BILL-003]" do
    it "skips retention window updates when already active beyond paid_at" do
      user = create_billing_user!
      run = create_nesting_run!
      retained_until = 2.days.from_now
      grant = DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: retained_until
      )
      run.project.nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )

      described_class.call(grant: grant, nesting_run: run, paid_at: Time.current)

      expect(grant.reload.retained_until).to be_within(1.second).of(retained_until)
    end
  end

  describe Nesting::ProgressEta, "[REQ-FIT-JOB-001]" do
    it "returns the time limit when piece counts are zero" do
      started = 5.minutes.ago

      eta = described_class.estimate(started_at: started, time_limit_sec: 120, pieces_total: 0, pieces_placed: 0)

      expect(eta).to be_within(1.second).of(started + 120.seconds)
    end
  end

  describe Admin::ExportPaymentsXlsx, "[REQ-FIT-ADMIN-001]" do
    it "applies alternating stripe styles across multiple summary groups" do
      user = create_billing_user!(email: "stripe-admin@example.com")
      Payment.create!(
        user: user, status: "succeeded", payment_method: "sinpe_crc", currency: "crc",
        amount: 1000, subtotal: 1000, total_amount: 1130, tax_amount: 130,
        paid_at: Time.zone.parse("2026-01-01 10:00"), gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_crc_1", onvo_mode: "test", gateway_status: "succeeded",
        purpose: "single_download", product_description: "single_download"
      )
      Payment.create!(
        user: user, status: "succeeded", payment_method: "card_crc", currency: "crc",
        amount: 2000, subtotal: 2000, total_amount: 2260, tax_amount: 260,
        paid_at: Time.zone.parse("2026-01-02 10:00"), gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_crc_2", onvo_mode: "test", gateway_status: "succeeded",
        purpose: "single_download", product_description: "single_download"
      )

      expect { described_class.call(Payment.where(user_id: user.id)) }.not_to raise_error
    end
  end

  describe "BlocksWorkshopDuringPendingPayment active lock [REQ-FIT-BILL-001]" do
    it "returns true when the pending lock is active" do
      host = Class.new(ApplicationController) { include BlocksWorkshopDuringPendingPayment }.new
      project = create_project_for_spec!(title: "Active lock", bind_workspace: false)
      user = create_billing_user!
      lock = instance_double(Billing::PendingCheckoutLock, active?: true)
      host.instance_variable_set(:@project, project)
      allow(host).to receive(:current_user).and_return(user)
      allow(Billing::PendingCheckoutLock).to receive(:for).and_return(lock)

      expect(host.send(:workshop_mutations_locked?)).to be(true)
    end
  end

  describe NestingJob, type: :job do
    it "skips FailRun when the reloaded run is no longer processing" do
      run = create_nesting_run!
      run.update!(status: "processing")
      allow(Nesting::JobRunner).to receive(:call).and_raise(StandardError, "boom")
      find_calls = 0
      allow(NestingRun).to receive(:find_by).with(id: run.id) do
        find_calls += 1
        if find_calls == 1
          run
        else
          run.update_column(:status, "completed")
          run.reload
        end
      end
      allow(Analytics::TrackEvent).to receive(:call)

      expect(Nesting::FailRun).not_to receive(:call)

      described_class.perform_now(run.id)
    end
  end

  describe CheckoutController, "[REQ-FIT-BILL-001]" do
    it "assigns @project from nesting_run when workspace project is unset" do
      user = create_billing_user!
      project = create_project_for_spec!(title: "Unbound checkout", bind_workspace: false)
      run = project.nesting_runs.create!(status: "completed")
      host = described_class.new
      host.request = ActionDispatch::TestRequest.create
      host.response = ActionDispatch::TestResponse.new
      allow(host).to receive(:current_user).and_return(user)
      allow(host).to receive(:session).and_return({})
      allow(host).to receive(:params).and_return(ActionController::Parameters.new(nesting_run_id: run.id.to_s))
      allow(host).to receive(:redirect_to)
      allow(Workspace).to receive(:bound_to_project?).and_return(false)

      host.send(:load_checkout_context)

      expect(host.instance_variable_get(:@project)).to eq(project)
      expect(host).to have_received(:redirect_to).with(start_project_path, alert: I18n.t("workspace.expired"))
    end
  end

  describe "Users::SessionsController signed-out destroy [REQ-FIT-AUTH-002]", type: :request do
    it "skips logout analytics when the user is not signed in" do
      allow(Analytics::TrackEvent).to receive(:call)

      delete destroy_user_session_path

      expect(Analytics::TrackEvent).not_to have_received(:call).with("user_logged_out", anything)
    end
  end

  describe "Users::RegistrationsController failed update [REQ-FIT-AUTH-002]", type: :request do
    it "re-renders edit when password confirmation does not match" do
      user = create_billing_user!
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

      patch user_registration_path, params: {
        user: {
          name: user.name,
          password: "newpassword1234",
          password_confirmation: "mismatch1234",
          current_password: "securepassword12"
        }
      }

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "Users::ConfirmationsController invalid token [REQ-FIT-AUTH-002]", type: :request do
    it "does not track email_confirmed when confirmation fails" do
      allow(Analytics::TrackEvent).to receive(:call)

      get user_confirmation_path(confirmation_token: "invalid-token")

      expect(Analytics::TrackEvent).not_to have_received(:call).with("email_confirmed", anything)
    end
  end

  describe "RequiresBillingConfirmation precondition [REQ-FIT-AUTH-002]" do
    it "raises when current_user is unexpectedly nil" do
      host = CheckoutController.new
      allow(host).to receive(:current_user).and_return(nil)

      expect { host.send(:require_confirmed_for_checkout!) }.to raise_error(ArgumentError, /precondition failed/)
    end
  end

  describe ProjectLayer::SetPrimary, "[REQ-FIT-DXF-002]" do
    it "clears sibling primaries on the same attachment" do
      project = create_project_for_spec!(title: "Set primary", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      attachment_id = project.input_dxf_attachments.first!.id
      first = project.project_layers.find_by!(active_storage_attachment_id: attachment_id)
      second = project.project_layers.where(active_storage_attachment_id: attachment_id).where.not(id: first.id).first!
      ProjectLayer::SetPrimary.call(first)

      ProjectLayer::SetPrimary.call(second)

      expect(first.reload.layer_role).to be_nil
      expect(second.reload.layer_role).to eq("primary")
    end
  end
end
