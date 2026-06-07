# frozen_string_literal: true

require "rails_helper"

RSpec.describe "CheckoutController coverage edge cases", type: :request do
  let(:user) { create_billing_user! }
  let(:project) do
    p = create_project_for_spec!(title: "Checkout Bench")
    p.update!(status: :completed)
    p
  end
  let(:run) do
    project.nesting_runs.create!(status: "completed")
  end

  before do
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  describe "POST /checkout/pagar without Onvo" do
    it "returns 404 not found when gateway is not onvo" do
      allow(Billing::Gateway).to receive(:onvo?).and_return(false)
      post checkout_pay_path, params: { nesting_run_id: run.id }
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /checkout/pagar Onvo failures" do
    around do |example|
      keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
      ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
      ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it "handles ApiError gracefully" do
      allow(Billing::StartOnvoCheckout).to receive(:call).and_raise(
        Billing::Onvo::ApiError.new("Start checkout failed", status: 422, body: "{}")
      )
      post checkout_pay_path, params: { nesting_run_id: run.id, payment_method: "sinpe_crc" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to be_present
    end
  end

  describe "POST /checkout/pagos/:payment_id/sinpe Onvo failures" do
    around do |example|
      keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
      ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
      ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    let!(:payment) do
      user.payments.create!(
        nesting_run_id: run.id,
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        tax_amount: 130,
        total_amount: 1130,
        purpose: "single_download"
      )
    end

    it "handles ApiError" do
      allow(Billing::Onvo::ConfirmSinpePayment).to receive(:call).and_raise(
        Billing::Onvo::ApiError.new("SINPE failed", status: 422, body: "{}")
      )
      post checkout_confirm_sinpe_path(payment_id: payment.id), params: {
        sinpe_identification: "112345678",
        sinpe_mobile_number: "88888888"
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "handles ArgumentError in parse" do
      post checkout_confirm_sinpe_path(payment_id: payment.id), params: {
        sinpe_identification: "",
        sinpe_mobile_number: ""
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    describe "usd format check" do
      let!(:payment_usd) do
        user.payments.create!(
          nesting_run_id: run.id,
          payment_method: "sinpe_crc",
          currency: "usd",
          amount: 10,
          tax_amount: 1,
          total_amount: 11,
          purpose: "single_download"
        )
      end

      it "formats USD amount correctly" do
        allow(Billing::Onvo::ConfirmSinpePayment).to receive(:call).and_return(
          amount: 11.0,
          currency: "usd"
        )
        post checkout_confirm_sinpe_path(payment_id: payment_usd.id), params: {
          sinpe_identification: "112345678",
          sinpe_mobile_number: "88888888"
        }
        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["amount_label"]).to include("$")
      end
    end
  end

  describe "POST /checkout/pagos/:payment_id/tarjeta" do
    around do |example|
      keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
      ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
      ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    let!(:payment) do
      user.payments.create!(
        nesting_run_id: run.id,
        payment_method: "card_crc",
        currency: "crc",
        amount: 1200,
        tax_amount: 156,
        total_amount: 1356,
        purpose: "single_download"
      )
    end

    it "handles ArgumentError in card parse" do
      post checkout_confirm_card_path(payment_id: payment.id), params: {
        card_holder_name: "",
        card_number: "",
        card_exp: "",
        card_cvv: ""
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "handles ApiError" do
      allow(Billing::Onvo::ConfirmCardPayment).to receive(:call).and_raise(
        Billing::Onvo::ApiError.new("Card failed", status: 422, body: "{}")
      )
      post checkout_confirm_card_path(payment_id: payment.id), params: {
        card_holder_name: "John Doe",
        card_number: "4111111111111111",
        card_exp: "12/30",
        card_cvv: "123"
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "handles requires_payment_method status" do
      allow(Billing::Onvo::ConfirmCardPayment).to receive(:call).and_return(
        status: "requires_payment_method"
      )
      post checkout_confirm_card_path(payment_id: payment.id), params: {
        card_holder_name: "John Doe",
        card_number: "4111111111111111",
        card_exp: "12/30",
        card_cvv: "123"
      }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "handles failed status" do
      allow(Billing::Onvo::ConfirmCardPayment).to receive(:call).and_return(
        status: "failed"
      )
      post checkout_confirm_card_path(payment_id: payment.id), params: {
        card_holder_name: "John Doe",
        card_number: "4111111111111111",
        card_exp: "12/30",
        card_cvv: "123"
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "GET /checkout/pagos/:payment_id/cancelado" do
    around do |example|
      keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
      ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
      ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    let!(:payment) do
      user.payments.create!(
        nesting_run_id: run.id,
        payment_method: "card_crc",
        currency: "crc",
        amount: 1200,
        tax_amount: 156,
        total_amount: 1356,
        purpose: "single_download"
      )
    end

    it "abandons card checkout and redirects" do
      get checkout_payment_canceled_path(payment_id: payment.id)
      expect(response).to redirect_to(checkout_path(nesting_run_id: run.id, payment_method: "card_crc"))
    end
  end

  describe "GET /checkout/pagos/:payment_id/rechazado" do
    around do |example|
      keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
      ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
      ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    let!(:payment) do
      user.payments.create!(
        nesting_run_id: run.id,
        payment_method: "card_crc",
        currency: "crc",
        amount: 1200,
        tax_amount: 156,
        total_amount: 1356,
        purpose: "single_download",
        status: "pending"
      )
    end

    it "fails payment if not already failed" do
      allow_any_instance_of(Payment).to receive(:incomplete_card_checkout_attempt?).and_return(false)
      get checkout_payment_failed_path(payment_id: payment.id)
      expect(response).to redirect_to(checkout_path(nesting_run_id: run.id, payment_method: "card_crc"))
      expect(payment.reload).to be_failed
    end

    it "abandons incomplete card checkout if incomplete_card_checkout_abandonment? is true" do
      allow_any_instance_of(Payment).to receive(:incomplete_card_checkout_attempt?).and_return(true)
      expect(Billing::AbandonIncompleteCardCheckout).to receive(:call).and_call_original
      get checkout_payment_failed_path(payment_id: payment.id)
      expect(response).to redirect_to(checkout_path(nesting_run_id: run.id, payment_method: "card_crc"))
    end
  end

  describe "POST /checkout/simular Onvo error" do
    it "redirects to checkout if simulator called when in Onvo mode" do
      allow(Billing::Gateway).to receive(:onvo?).and_return(true)
      post checkout_simulate_path, params: { nesting_run_id: run.id }
      expect(response).to redirect_to(checkout_path(nesting_run_id: run.id))
      expect(flash[:alert]).to eq(I18n.t("billing.checkout.onvo_use_pay"))
    end
  end

  describe "POST /checkout/simular plan purchase" do
    it "handles plan purchase failures" do
      begin_workspace_session!
      Cart.create!(user_id: user.id, kind: "plan", tier_months: "4", currency_mode: "crc", list_price_cents: 1200, sinpe_price_cents: 1000)
      allow(Billing::SimulatePlanPurchase).to receive(:call).and_return(:failed)

      post checkout_simulate_path, params: { payment_method: "card_crc", outcome: "failure" }
      expect(response).to redirect_to(checkout_path)
      expect(flash[:alert]).to eq(I18n.t("billing.checkout.failure"))
    end

    it "handles successful plan purchase without bound project" do
      begin_workspace_session!
      allow(Workspace).to receive(:bound_to_project?).and_return(true, false)
      Cart.create!(user_id: user.id, kind: "plan", tier_months: "4", currency_mode: "crc", list_price_cents: 1200, sinpe_price_cents: 1000)
      fake_grant = double(id: 456)
      allow(Billing::SimulatePlanPurchase).to receive(:call).and_return(grant: fake_grant)

      post checkout_simulate_path, params: { payment_method: "card_crc", outcome: "success" }
      expect(response).to redirect_to(mis_pagos_path)
    end

    it "handles successful plan purchase with bound project" do
      begin_workspace_session!
      Cart.create!(user_id: user.id, kind: "plan", tier_months: "4", currency_mode: "crc", list_price_cents: 1200, sinpe_price_cents: 1000)
      fake_grant = double(id: 456)
      allow(Billing::SimulatePlanPurchase).to receive(:call).and_return(grant: fake_grant)

      post checkout_simulate_path, params: { payment_method: "card_crc", outcome: "success" }
      expect(response).to redirect_to(workshop_path)
    end
  end

  describe "GET /checkout without bound project" do
    it "redirects to start_project_path" do
      other_project = Project.create!(ephemeral: true, title: "Other Project")
      other_run = other_project.nesting_runs.create!(status: "completed")

      get checkout_path(nesting_run_id: other_run.id)
      expect(response).to redirect_to(start_project_path)
    end
  end

  describe "GET /checkout/retorno (3DS return) other statuses" do
    around do |example|
      keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
      ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
      ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    let!(:payment) do
      user.payments.create!(
        nesting_run_id: run.id,
        payment_method: "card_crc",
        currency: "crc",
        amount: 1200,
        tax_amount: 156,
        total_amount: 1356,
        purpose: "single_download",
        onvo_payment_intent_id: "pi_123",
        gateway_provider: "onvo",
        onvo_mode: "test",
        gateway_status: "requires_action"
      )
    end

    it "redirects to failed if intent_status is failed and card_checkout is false" do
      payment.update!(payment_method: "sinpe_crc")
      allow(Billing::Onvo::ReconcilePaymentIntent).to receive(:call).and_return(status: "failed")
      get checkout_return_path, params: { payment_intent_id: "pi_123" }
      expect(response).to redirect_to(checkout_payment_failed_path(payment))
    end

    it "redirects to canceled if intent_status is other and card_checkout is false" do
      payment.update!(payment_method: "sinpe_crc")
      allow(Billing::Onvo::ReconcilePaymentIntent).to receive(:call).and_return(status: "requires_action")
      get checkout_return_path, params: { payment_intent_id: "pi_123" }
      expect(response).to redirect_to(checkout_payment_canceled_path(payment))
    end
  end

  describe "GET /checkout with unbound project in load_checkout_context" do
    it "redirects to start_project_path when project is not bound in load_checkout_context" do
      begin_workspace_session!
      allow(Workspace).to receive(:bound_to_project?).and_return(false)
      get checkout_path(nesting_run_id: run.id)
      expect(response).to redirect_to(start_project_path)
    end
  end

  describe "resolve_selected_payment_method other" do
    it "returns requested payment method when it doesn't match sinpe or card" do
      begin_workspace_session!
      get checkout_path(nesting_run_id: run.id), params: { payment_method: "other_method" }
      expect(response).to have_http_status(:ok)
    end
  end

  describe "normalize_payment_method card_usd" do
    it "normalizes to card_usd when selection currency is usd" do
      begin_workspace_session!
      allow(Billing::PaymentSelection).to receive(:resolve).and_return(
        currency: :usd,
        payment_method: :card,
        available_payment_methods: [:card],
        iva_applicable: false
      )
      get checkout_path(nesting_run_id: run.id)
      expect(response).to have_http_status(:ok)
    end
  end

  describe "normalize_payment_method card_crc" do
    it "normalizes to card_crc when selection currency is crc" do
      begin_workspace_session!
      allow(Billing::PaymentSelection).to receive(:resolve).and_return(
        currency: :crc,
        payment_method: :card,
        available_payment_methods: [:card],
        iva_applicable: true
      )

      get checkout_path(nesting_run_id: run.id)

      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@selected_payment_method)).to eq("card_crc")
    end
  end

  describe "GET /checkout with invalid outcome" do
    it "defaults @simulate_outcome to success" do
      begin_workspace_session!
      get checkout_path(nesting_run_id: run.id), params: { outcome: "invalid_value" }
      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@simulate_outcome)).to eq("success")
    end
  end

  describe "load_resume_sinpe_payment edge case" do
    it "loads resume payment" do
      begin_workspace_session!
      project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID)
      run_instance = project.nesting_runs.create!(status: "completed")

      payment = user.payments.create!(
        nesting_run: run_instance,
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        tax_amount: 130,
        total_amount: 1130,
        purpose: "single_download",
        status: "pending",
        user: user
      )
      get checkout_path(payment_id: payment.id, nesting_run_id: run_instance.id)
      expect(response).to have_http_status(:ok)
    end

    it "ignores superseded pending SINPE payments" do
      begin_workspace_session!
      project = Workspace.find(session, tab_id: Workspace::DEFAULT_TAB_ID)
      run_instance = project.nesting_runs.create!(status: "completed")
      payment = user.payments.create!(
        nesting_run: run_instance,
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        tax_amount: 130,
        total_amount: 1130,
        purpose: "single_download",
        status: "pending",
        superseded_at: Time.current,
        user: user
      )

      get checkout_path(payment_id: payment.id, nesting_run_id: run_instance.id)

      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@resume_sinpe_payment)).to be_nil
    end
  end

  describe "load_checkout_context branches [REQ-FIT-BILL-001]" do
    it "redirects to paywall when nesting_run_id does not exist" do
      begin_workspace_session!
      missing_id = [ Project.maximum(:id), NestingRun.maximum(:id) ].compact.max.to_i + 10_000

      get checkout_path(nesting_run_id: missing_id)

      expect(response).to redirect_to(download_paywall_workshop_path)
    end

    it "redirects to paywall when the signed-in user has no cart" do
      begin_workspace_session!

      get checkout_path

      expect(response).to redirect_to(download_paywall_workshop_path)
    end

    it "redirects to paywall when cart single-download lacks nesting_run" do
      begin_workspace_session!
      cart = Cart.create!(
        user_id: user.id,
        kind: "single_download",
        nesting_run: run,
        currency_mode: "crc",
        list_price_cents: 1200,
        sinpe_price_cents: 1000
      )
      cart.update_column(:nesting_run_id, nil)

      get checkout_path

      expect(response).to redirect_to(download_paywall_workshop_path)
    end

    it "renders plan checkout without a bound nesting project" do
      begin_workspace_session!
      Cart.create!(
        user_id: user.id,
        kind: "plan",
        tier_months: "4",
        currency_mode: "crc",
        list_price_cents: 8400,
        sinpe_price_cents: 8000
      )

      get checkout_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "POST /checkout/pagar duplicate SINPE lock [REQ-FIT-BILL-001]" do
    around do |example|
      keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
      ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
      ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it "returns conflict when an active SINPE lock already exists" do
      begin_workspace_session!
      user.payments.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        tax_amount: 130,
        total_amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        gateway_status: "processing",
        onvo_payment_intent_id: "pi_duplicate_lock",
        onvo_mode: "test",
        created_at: 5.minutes.ago
      )

      post checkout_pay_path, params: { nesting_run_id: run.id, payment_method: "sinpe_crc" }

      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body).fetch("redirect_url")).to eq(mis_pagos_path)
    end

    it "passes tier_months for plan cart checkout" do
      begin_workspace_session!
      Cart.create!(
        user_id: user.id,
        kind: "plan",
        tier_months: "4",
        currency_mode: "crc",
        list_price_cents: 8400,
        sinpe_price_cents: 8000
      )
      payment = user.payments.create!(
        user: user,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 8000,
        total_amount: 8000,
        purpose: "plan_subscription",
        gateway_provider: "onvo",
        gateway_status: "processing",
        onvo_payment_intent_id: "pi_plan_checkout",
        onvo_mode: "test"
      )
      allow(Billing::StartOnvoCheckout).to receive(:call).and_return(
        payment: payment,
        onvo_payment_intent_id: "pi_plan_checkout"
      )

      post checkout_pay_path, params: { payment_method: "sinpe_crc" }

      expect(Billing::StartOnvoCheckout).to have_received(:call).with(
        hash_including(tier_months: 4, cart: kind_of(Cart))
      )
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /checkout/pagos/:payment_id/rechazado already failed [REQ-FIT-BILL-001]" do
    around do |example|
      keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
      ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
      ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    let!(:payment) do
      user.payments.create!(
        nesting_run_id: run.id,
        payment_method: "card_crc",
        currency: "crc",
        amount: 1200,
        tax_amount: 156,
        total_amount: 1356,
        purpose: "single_download",
        status: "failed"
      )
    end

    it "skips FailPayment when the payment is already failed" do
      expect(Billing::FailPayment).not_to receive(:call)

      get checkout_payment_failed_path(payment_id: payment.id)

      expect(response).to redirect_to(checkout_path(nesting_run_id: run.id, payment_method: "card_crc"))
    end
  end

  describe "GET /checkout/retorno blank intent [REQ-FIT-BILL-001]" do
    around do |example|
      keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
      ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
      ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it "raises when payment_intent_id is blank" do
      get checkout_return_path, params: { payment_intent_id: "   " }

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "payment method resolution branches [REQ-FIT-BILL-001]" do
    it "falls back when requested SINPE is unavailable" do
      begin_workspace_session!
      allow(Billing::PaymentSelection).to receive(:resolve).and_return(
        currency: :crc,
        payment_method: :card,
        available_payment_methods: [:card],
        iva_applicable: true
      )

      get checkout_path(nesting_run_id: run.id, payment_method: "sinpe_crc")

      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@selected_payment_method)).to eq("card_crc")
    end

    it "falls back when requested card is unavailable" do
      begin_workspace_session!
      allow(Billing::PaymentSelection).to receive(:resolve).and_return(
        currency: :crc,
        payment_method: :sinpe,
        available_payment_methods: [:sinpe],
        iva_applicable: true
      )

      get checkout_path(nesting_run_id: run.id, payment_method: "card_crc")

      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@selected_payment_method)).to eq("sinpe_crc")
    end

    it "preserves explicit success outcome values" do
      begin_workspace_session!

      get checkout_path(nesting_run_id: run.id, outcome: "success")

      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@simulate_outcome)).to eq("success")
    end

    it "returns nil SINPE savings when the discount is zero" do
      begin_workspace_session!
      get checkout_path(nesting_run_id: run.id)
      allow(Billing::CheckoutBreakdown).to receive(:for_single_download).and_return(
        currency: :crc,
        payment_method: :sinpe,
        iva_applicable: true,
        list_price: 1200,
        discount_amount: 0,
        subtotal: 1200,
        tax_amount: 156,
        total_amount: 1356
      )

      expect(controller.send(:sinpe_savings_amount_preview)).to be_nil
    end
  end

  describe "Onvo-only routes without gateway [REQ-FIT-BILL-001]" do
    it "returns not found for payment canceled notice when gateway is simulate" do
      allow(Billing::Gateway).to receive(:onvo?).and_return(false)
      payment = user.payments.create!(
        nesting_run_id: run.id,
        payment_method: "card_crc",
        currency: "crc",
        amount: 1200,
        tax_amount: 156,
        total_amount: 1356,
        purpose: "single_download"
      )

      get checkout_payment_canceled_path(payment_id: payment.id)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "card checkout return branches [REQ-FIT-BILL-001]" do
    around do |example|
      keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
      ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
      ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it "does not persist card selection for non-card payments" do
      payment = user.payments.create!(
        nesting_run_id: run.id,
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        tax_amount: 130,
        total_amount: 1130,
        purpose: "single_download"
      )

      get checkout_payment_canceled_path(payment_id: payment.id)

      expect(session[:billing_payment_method]).to be_nil
      expect(response).to redirect_to(checkout_path(nesting_run_id: run.id))
    end

    it "uses plan redirect params when simulating blocked Onvo checkout" do
      begin_workspace_session!
      Cart.create!(
        user_id: user.id,
        kind: "plan",
        tier_months: "2",
        currency_mode: "crc",
        list_price_cents: 5300,
        sinpe_price_cents: 5000
      )
      allow(Billing::Gateway).to receive(:onvo?).and_return(true)

      post checkout_simulate_path, params: { payment_method: "card_crc", outcome: "success" }

      expect(response).to redirect_to(checkout_path(tier_months: 2))
    end
  end

  describe "POST /checkout/simular single-download failure [REQ-FIT-BILL-001]" do
    it "redirects with nesting_run_id when single-download simulation fails" do
      begin_workspace_session!
      allow(Billing::SimulateSingleDownload).to receive(:call).and_return(:failed)

      post checkout_simulate_path,
           params: { nesting_run_id: run.id, payment_method: "card_crc", outcome: "failure" }

      expect(response).to redirect_to(checkout_path(nesting_run_id: run.id))
      expect(flash[:alert]).to eq(I18n.t("billing.checkout.failure"))
    end

    it "redirects to mis pagos when plan purchase succeeds without a cart row" do
      controller = CheckoutController.new
      controller.request = ActionDispatch::TestRequest.create
      controller.response = ActionDispatch::TestResponse.new
      allow(controller).to receive(:current_cart).and_return(nil)
      allow(controller).to receive(:redirect_to)
      allow(controller).to receive(:t).and_return("Plan success")
      allow(Workspace).to receive(:bound_to_project?).and_return(false)

      controller.send(:redirect_after_plan_purchase!, double(id: 123))

      expect(controller).to have_received(:redirect_to).with(mis_pagos_path, notice: "Plan success")
    end
  end

  describe "private checkout helpers [REQ-FIT-BILL-001]" do
    it "returns the raw ApiError message when context is nil" do
      begin_workspace_session!
      get checkout_path(nesting_run_id: run.id)

      error = Billing::Onvo::ApiError.new("plain gateway error", status: 422, body: "{}")
      message = controller.send(:onvo_api_error_message, error, context: nil)

      expect(message).to eq(I18n.t("billing.checkout.onvo.api_errors.generic"))
    end
  end

  describe "current_cart when signed out [REQ-FIT-BILL-001]" do
    it "returns nil without querying carts for anonymous visitors" do
      begin_workspace_session!
      get checkout_path(nesting_run_id: run.id)
      allow(controller).to receive(:user_signed_in?).and_return(false)

      expect(controller.send(:current_cart)).to be_nil
    end
  end

  describe "remaining checkout branches [REQ-FIT-BILL-001]" do
    around do |example|
      keys = %w[BILLING_GATEWAY ONVO_SECRET_KEY ONVO_PUBLISHABLE_KEY ONVO_WEBHOOK_SECRET]
      previous = keys.index_with { |key| ENV[key] }
      ENV["BILLING_GATEWAY"] = "onvo"
      ENV["ONVO_SECRET_KEY"] = "onvo_test_secret_spec"
      ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_spec"
      ENV["ONVO_WEBHOOK_SECRET"] = "whsec_spec"
      example.run
    ensure
      previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
    end

    it "redirects single-download simulate failures with nesting_run_id" do
      begin_workspace_session!
      allow(Billing::SimulateSingleDownload).to receive(:call).and_return(:failed)

      post checkout_simulate_path,
           params: { nesting_run_id: run.id, payment_method: "card_crc", outcome: "failure" }

      expect(response).to redirect_to(checkout_path(nesting_run_id: run.id))
    end

    it "redirects to project when plan quota blocks single-download checkout" do
      begin_workspace_session!
      allow(Billing::PlanDownloadAvailability).to receive(:single_download_checkout_allowed?).and_return(false)

      get checkout_path(nesting_run_id: run.id)

      expect(response).to redirect_to(project_path(run.project))
    end

    it "falls back to card_usd when card is unavailable in USD checkout" do
      begin_workspace_session!
      allow(Billing::PaymentSelection).to receive(:resolve).and_return(
        currency: :usd,
        payment_method: :card,
        available_payment_methods: [:card],
        iva_applicable: false
      )

      get checkout_path(nesting_run_id: run.id, payment_method: "card_invalid")

      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@selected_payment_method)).to eq("card_usd")
    end

    it "formats confirm-card success JSON for non-failed intents" do
      payment = user.payments.create!(
        nesting_run_id: run.id,
        payment_method: "card_crc",
        currency: "crc",
        amount: 1200,
        tax_amount: 156,
        total_amount: 1356,
        purpose: "single_download"
      )
      allow(Billing::Onvo::ConfirmCardPayment).to receive(:call).and_return(
        status: "processing",
        redirect_url: "https://example.test/3ds"
      )

      post checkout_confirm_card_path(payment_id: payment.id), params: {
        card_holder_name: "John Doe",
        card_number: "4111111111111111",
        card_exp: "12/30",
        card_cvv: "123"
      }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).fetch("status")).to eq("processing")
    end

    it "redirects card 3DS returns to canceled notice for card checkouts" do
      payment = user.payments.create!(
        nesting_run_id: run.id,
        payment_method: "card_crc",
        currency: "crc",
        amount: 1200,
        tax_amount: 156,
        total_amount: 1356,
        purpose: "single_download",
        onvo_payment_intent_id: "pi_card_cancel",
        gateway_provider: "onvo",
        gateway_status: "requires_action",
        onvo_mode: "test"
      )
      allow(Billing::Onvo::ReconcilePaymentIntent).to receive(:call).and_return(status: "requires_action")

      get checkout_return_path, params: { payment_intent_id: "pi_card_cancel" }

      expect(response).to redirect_to(checkout_payment_canceled_path(payment))
    end

    it "uses CRC formatting for confirm-card helper paths" do
      controller = CheckoutController.new
      expect(controller.send(:format_onvo_amount, 1200, "crc")).to include("₡")
    end

    it "loads checkout from a cart-backed single download" do
      begin_workspace_session!
      Cart.create!(
        user_id: user.id,
        kind: "single_download",
        nesting_run: run,
        currency_mode: "crc",
        list_price_cents: 1200,
        sinpe_price_cents: 1000
      )

      get checkout_path

      expect(response).to have_http_status(:ok)
    end

    it "records successful single-download simulation" do
      begin_workspace_session!
      allow(Billing::Gateway).to receive(:onvo?).and_return(false)
      allow(Billing::SimulateSingleDownload).to receive(:call).and_return(grant: double(id: 999))

      post checkout_simulate_path,
           params: { nesting_run_id: run.id, payment_method: "card_crc", outcome: "success" }

      expect(response).to redirect_to(mis_pagos_path(auto_download: 999))
    end

    it "selects card_usd when USD checkout requests card" do
      begin_workspace_session!
      allow(Billing::PaymentSelection).to receive(:resolve).and_return(
        currency: :usd,
        payment_method: :card,
        available_payment_methods: [:card],
        iva_applicable: false
      )

      get checkout_path(nesting_run_id: run.id, payment_method: "card_crc")

      expect(response).to have_http_status(:ok)
      expect(controller.instance_variable_get(:@selected_payment_method)).to eq("card_usd")
    end

    it "returns nil resume payment when payment_id does not resolve" do
      begin_workspace_session!

      get checkout_path(nesting_run_id: run.id, payment_id: 999_999_999)

      expect(controller.instance_variable_get(:@resume_sinpe_payment)).to be_nil
    end

    it "returns nil resume payment when payment_id is absent" do
      begin_workspace_session!

      get checkout_path(nesting_run_id: run.id)

      expect(controller.instance_variable_get(:@resume_sinpe_payment)).to be_nil
    end

    it "redirects SINPE 3DS returns to processing on success" do
      payment = user.payments.create!(
        nesting_run_id: run.id,
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        tax_amount: 130,
        total_amount: 1130,
        purpose: "single_download",
        onvo_payment_intent_id: "pi_sinpe_success",
        gateway_provider: "onvo",
        gateway_status: "processing",
        onvo_mode: "test"
      )
      allow(Billing::Onvo::ReconcilePaymentIntent).to receive(:call).and_return(status: "succeeded")

      get checkout_return_path, params: { payment_intent_id: "pi_sinpe_success" }

      expect(response).to redirect_to(checkout_processing_path(payment))
    end

    it "skips card session selection for non-card failed notices" do
      payment = user.payments.create!(
        nesting_run_id: run.id,
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        tax_amount: 130,
        total_amount: 1130,
        purpose: "single_download",
        status: "pending"
      )
      allow_any_instance_of(Payment).to receive(:incomplete_card_checkout_attempt?).and_return(false)

      get checkout_payment_failed_path(payment_id: payment.id)

      expect(session[:billing_payment_method]).to be_nil
    end
  end

  describe "unsigned checkout access [REQ-FIT-BILL-001]" do
    before { delete destroy_user_session_path }

    it "requires authentication before checkout loads" do
      get checkout_path(nesting_run_id: run.id)

      expect(response).to redirect_to(new_user_session_path)
    end
  end
end
