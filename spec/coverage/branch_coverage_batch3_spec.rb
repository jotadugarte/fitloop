# frozen_string_literal: true

require "rails_helper"

# Batch 3: controller, concern, and helper branch gaps from analyze_coverage.rb.
RSpec.describe "Branch coverage batch 3" do
  include BillingModelHelpers

  describe "ApplicationController [REQ-FIT-AUTH-002]" do
    let(:controller) { ApplicationController.new }

    before { controller.request = ActionDispatch::TestRequest.create }

    it "merges guest cart and clears session keys when a User signs in" do
      user = create_billing_user!
      session = { cart_guest_token: "guest-tok", anonymous_session_key: "anon-key", pending_cart: { kind: "plan" } }
      allow(controller).to receive(:session).and_return(session)
      allow(Billing::CartMergeOnLogin).to receive(:call)
      allow(Analytics::MergeAnonymousSession).to receive(:call)

      expect(controller.after_sign_in_path_for(user)).to eq("/")
      expect(Billing::CartMergeOnLogin).to have_received(:call).with(user: user, guest_token: "guest-tok")
      expect(Analytics::MergeAnonymousSession).to have_received(:call).with("anon-key", user.id)
      expect(session).not_to have_key(:cart_guest_token)
      expect(session).not_to have_key(:pending_cart)
    end

    it "uses the minimal layout for Devise controllers" do
      allow(controller).to receive(:devise_controller?).and_return(true)

      expect(controller.send(:layout_for_controller)).to eq("minimal")
    end

    it "uses the application layout for non-Devise controllers" do
      allow(controller).to receive(:devise_controller?).and_return(false)

      expect(controller.send(:layout_for_controller)).to eq("application")
    end

    it "preserves an existing anonymous session key" do
      session = { anonymous_session_key: "existing-key" }
      allow(controller).to receive(:session).and_return(session)

      controller.send(:set_anonymous_session_key)

      expect(session[:anonymous_session_key]).to eq("existing-key")
    end
  end

  describe "LocaleSwitchable [REQ-FIT-UI-005]" do
    controller_class = Class.new(ApplicationController) do
      def self.name = "LocaleSwitchableBatch3Controller"
    end

    it "falls back to the default locale when no candidate is present" do
      host = controller_class.new
      host.request = ActionDispatch::TestRequest.create
      allow(host).to receive(:params).and_return(ActionController::Parameters.new)
      allow(host).to receive(:cookies).and_return({})
      allow(host).to receive(:session).and_return({})

      expect(host.send(:resolve_locale)).to eq(I18n.default_locale)
    end

    it "rejects unknown locale candidates" do
      host = controller_class.new
      host.request = ActionDispatch::TestRequest.create
      allow(host).to receive(:params).and_return(ActionController::Parameters.new(locale: "zz"))
      allow(host).to receive(:cookies).and_return({})
      allow(host).to receive(:session).and_return({})

      expect(host.send(:resolve_locale)).to eq(I18n.default_locale)
    end

    it "accepts locale candidates from the session" do
      host = controller_class.new
      host.request = ActionDispatch::TestRequest.create
      allow(host).to receive(:params).and_return(ActionController::Parameters.new)
      allow(host).to receive(:cookies).and_return({})
      allow(host).to receive(:session).and_return({ locale: "es" })

      expect(host.send(:resolve_locale)).to eq(:es)
    end

    it "persists locale to cookie and session" do
      host = controller_class.new
      host.request = ActionDispatch::TestRequest.create
      cookies_jar = ActionDispatch::Cookies::CookieJar.build(host.request, {})
      allow(host).to receive(:cookies).and_return(cookies_jar)
      allow(host).to receive(:session).and_return({})

      host.send(:persist_locale!, :es)

      expect(cookies_jar[:fitloop_locale]).to eq("es")
      expect(host.session[:locale]).to eq("es")
    end
  end

  describe "ResolvesWorkspaceTab [REQ-FIT-AUTH-001]" do
    controller_class = Class.new(ApplicationController) do
      include ResolvesWorkspaceTab
      def self.name = "ResolvesWorkspaceTabBatch3Controller"
    end

    it "prefers the workspace tab header over the cookie" do
      host = controller_class.new
      host.request = ActionDispatch::TestRequest.create
      host.request.headers[ResolvesWorkspaceTab::TAB_HEADER] = "header-tab"
      allow(host).to receive(:cookies).and_return({ ResolvesWorkspaceTab::TAB_COOKIE => "cookie-tab" })

      expect(host.send(:workspace_tab_id)).to eq("header-tab")
    end

    it "falls back to the cookie when the header is absent" do
      host = controller_class.new
      host.request = ActionDispatch::TestRequest.create
      allow(host).to receive(:cookies).and_return({ ResolvesWorkspaceTab::TAB_COOKIE => "cookie-tab" })

      expect(host.send(:workspace_tab_id)).to eq("cookie-tab")
    end
  end

  describe Billing::Gateway, "[REQ-FIT-BILL-001]" do
    around do |example|
      original = ENV["BILLING_GATEWAY"]
      example.run
    ensure
      ENV["BILLING_GATEWAY"] = original
    end

    it "reports simulate mode by default" do
      ENV.delete("BILLING_GATEWAY")

      expect(described_class.simulate?).to be(true)
      expect(described_class.onvo?).to be(false)
    end

    it "reports onvo mode when configured" do
      ENV["BILLING_GATEWAY"] = "onvo"

      expect(described_class.onvo?).to be(true)
      expect(described_class.simulate?).to be(false)
    end
  end

  describe Admin::VentasHelper, type: :helper do
    it "delegates payment method labels" do
      expect(helper.admin_payment_method_label("sinpe_crc")).to eq("SINPE Móvil")
    end

    it "delegates payment status labels" do
      expect(helper.admin_payment_status_label("succeeded")).to eq("Exitoso")
    end

    it "delegates payment purpose labels" do
      expect(helper.admin_payment_purpose_label("single_download")).to be_present
    end

    it "delegates product labels from payments" do
      payment = Payment.new(purpose: "single_download", product_description: "single_download")

      expect(helper.admin_payment_product_label(payment)).to be_present
    end

    it "delegates net collected totals" do
      payment = Payment.new(amount: 10, total_amount: 11.3)

      expect(helper.admin_payment_net_collected(payment)).to eq(11.3)
    end

    it "normalizes Form 150 export params" do
      params = helper.admin_form150_export_params({ status: [ "succeeded" ] })

      expect(params[:status]).to eq([ "succeeded" ])
    end
  end

  describe ProjectLayer, "[REQ-FIT-DXF-002]" do
    it "rejects a second primary layer on the same attachment" do
      project = create_project_for_spec!(title: "Primary validation", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      attachment_id = project.input_dxf_attachments.first!.id
      first = project.project_layers.find_by!(active_storage_attachment_id: attachment_id)
      second = project.project_layers.where(active_storage_attachment_id: attachment_id).where.not(id: first.id).first!
      first.update!(layer_role: :primary)

      second.layer_role = :primary

      expect(second).not_to be_valid
      expect(second.errors[:layer_role]).to be_present
    end

    it "allows primary assignment when no sibling primary exists" do
      project = create_project_for_spec!(title: "Solo primary", bind_workspace: false)
      sample_dxf = Rails.root.join("nesting_engine/tests/fixtures/sample_piece.dxf")
      project.input_dxf.attach(io: File.open(sample_dxf), filename: "piece.dxf", content_type: "application/dxf")
      Dxf::LayerSyncPerFile.call(project)
      layer = project.project_layers.first!

      layer.layer_role = :primary

      expect(layer).to be_valid
    end
  end

  describe ConfirmationsController, "[REQ-FIT-AUTH-002]", type: :request do
    it "renders the pending confirmation page for signed-in users" do
      user = create_billing_user!
      user.update!(confirmed_at: nil)
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

      get email_confirmation_pending_path

      expect(response).to have_http_status(:ok)
    end
  end

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
      expect(grant.retained_until).to be_present
    end
  end

  describe NestingJob, type: :job do
    it "emits nest telemetry when the run finishes outside processing" do
      run = create_nesting_run!
      run.update!(status: "processing", started_at: 1.minute.ago)
      allow(Nesting::JobRunner).to receive(:call) { run.update!(status: "completed", finished_at: Time.current) }
      allow(Analytics::TrackEvent).to receive(:call)

      described_class.perform_now(run.id)

      expect(Analytics::TrackEvent).to have_received(:call).with("nest_completed", hash_including(nesting_run_id: run.id))
    end
  end
end
