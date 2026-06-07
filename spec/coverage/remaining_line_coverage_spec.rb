# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Remaining line coverage gaps" do
  include BillingModelHelpers

  describe "Billing::FulfillPayment unsupported purpose [REQ-FIT-BILL-001]" do
    it "raises for unknown payment purposes" do
      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2.5,
        total_amount: 2.5,
        purpose: "single_download"
      )
      payment.update_column(:purpose, "legacy_product")

      expect do
        Billing::FulfillPayment.call(payment: payment)
      end.to raise_error(ArgumentError, /unsupported payment purpose/)
    end
  end

  describe "Billing::GeoLite2 defensive lookups [REQ-FIT-BILL-001]" do
    after do
      Billing::GeoLite2.send(:remove_instance_variable, :@client) if Billing::GeoLite2.instance_variable_defined?(:@client)
    end

    it "returns nil for invalid addresses" do
      expect(Billing::GeoLite2.country_code_for_ip("not-valid")).to be_nil
    end

    it "rescues lookup failures from the MMDB client" do
      path = "/tmp/geolite-spec.mmdb"
      maxmind = instance_double(MaxMindDB::Client)
      allow(maxmind).to receive(:lookup).and_raise(StandardError, "boom")

      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("GEOLITE2_COUNTRY_MMDB_PATH").and_return(path)
      allow(File).to receive(:file?).with(path).and_return(true)
      allow(MaxMindDB).to receive(:new).with(path).and_return(maxmind)

      expect(Billing::GeoLite2.country_code_for_ip("8.8.8.8")).to be_nil
    end
  end

  describe "Admin::VentasFilter invalid dates [REQ-FIT-ADMIN-001]" do
    it "ignores date filters that raise ArgumentError during parsing" do
      filter = Admin::VentasFilter.new({}, date_column: :paid_at)
      zone = instance_double(ActiveSupport::TimeZone)
      allow(filter).to receive(:cr_zone).and_return(zone)
      allow(zone).to receive(:parse).and_raise(ArgumentError)

      scope = Admin::ReportingScope.call
      scope = filter.send(:apply_start_date, scope, "bad-start")
      scope = filter.send(:apply_end_date, scope, "bad-end")

      expect(scope.to_sql).to eq(Admin::ReportingScope.call.to_sql)
    end
  end

  describe "Workshop::UxMode welcome variant [REQ-FIT-UI-003]" do
    it "uses the show variant outside setup mode" do
      project = create_project_for_spec!(title: "Taller mode", status: :ready)

      expect(Workshop::UxMode.new(project).welcome_variant).to eq(:show)
    end
  end

  describe "PersistWorkspaceLayerSelectionDraft auxiliary selection [REQ-FIT-UI-005]" do
    it "detects auxiliary layer picks in permitted params" do
      service = PersistWorkspaceLayerSelectionDraft.new(session: {}, params: {})
      permitted = {
        "1" => {
          "primary_layer_id" => "",
          "42" => { "auxiliary" => "1" }
        }
      }

      expect(service.send(:selection_in_params?, permitted)).to be(true)
    end
  end

  describe "Billing value-object equality [REQ-FIT-BILL-001]" do
    it "covers CountryCode and PaymentMethod hash semantics" do
      country = Billing::CountryCode.parse("CR")
      expect(country).to eq(Billing::CountryCode.parse("CR"))
      expect(country.hash).to eq(Billing::CountryCode.parse("CR").hash)

      method = Billing::PaymentMethod.parse("card_usd")
      expect(method).to eq(Billing::PaymentMethod.parse("card_usd"))
      expect(method.hash).to eq(Billing::PaymentMethod.parse("card_usd").hash)
    end
  end

  describe "Billing::Pricing resolver else branches [REQ-FIT-BILL-001]" do
    it "raises for unknown plan tiers in plan_price_triple and plan_key_prefix" do
      tier = instance_double(Billing::TierMonths, to_i: 99)
      allow(Billing::Pricing).to receive(:coerce_tier_months).and_return(tier)

      expect { Billing::Pricing.plan_price_triple(99) }.to raise_error(ArgumentError, /unknown plan tier_months: 99/)
      expect do
        Billing::Pricing.send(:plan_key_prefix, tier)
      end.to raise_error(ArgumentError, /unknown plan tier_months/)
    end

    it "raises for unsupported products in price-key resolvers" do
      expect do
        Billing::Pricing.send(:price_key_for_official_crc, product: :bundle, overage: false, tier_months: nil)
      end.to raise_error(ArgumentError, /unsupported product/)

      expect do
        Billing::Pricing.send(:price_key_for_sinpe_crc, product: :bundle, overage: false, tier_months: nil)
      end.to raise_error(ArgumentError, /unsupported product/)

      expect do
        Billing::Pricing.send(:price_key_for_official_usd, product: :bundle, overage: false, tier_months: nil)
      end.to raise_error(ArgumentError, /unsupported product/)
    end
  end

  describe "Dxf::LayerNamesReader.union [REQ-FIT-DXF-001]" do
    it "returns sorted layer names from catalog output" do
      allow(Dxf::LayerNamesReader).to receive(:catalog).and_return(
        [ { "name" => "B" }, { "name" => "A" } ]
      )

      expect(Dxf::LayerNamesReader.union([ "/tmp/a.dxf" ])).to eq(%w[A B])
    end
  end

  describe "StartsNesting#renesting? [REQ-FIT-JOB-001]" do
    it "detects completed projects with nested output attached" do
      project = create_project_for_spec!(title: "Renest", status: :completed)
      project.nested_dxf.attach(
        io: StringIO.new("nested"),
        filename: "nested.dxf",
        content_type: "application/dxf"
      )

      host = Class.new { include StartsNesting }.new

      expect(host.send(:renesting?, project)).to be(true)
    end
  end

  describe "BlocksWorkshopDuringPendingPayment [REQ-FIT-BILL-001]" do
    it "returns nil when no pending checkout lock exists" do
      host = Class.new(ApplicationController) do
        include BlocksWorkshopDuringPendingPayment
      end.new
      project = create_project_for_spec!(title: "No lock")
      host.instance_variable_set(:@project, project)
      allow(host).to receive(:current_user).and_return(nil)
      allow(Billing::PendingCheckoutLock).to receive(:for).with(project: project, user: nil).and_return(nil)

      expect(host.send(:workshop_mutations_locked?)).to be_nil
    end
  end

  describe "StoresWorkspaceReturnTo [REQ-FIT-AUTH-002]" do
    it "returns false for non session/registration controllers" do
      controller = Users::SessionsController.new

      allow(controller).to receive(:controller_name).and_return("passwords")

      expect(controller.send(:store_workspace_return_to_action?)).to be(false)
    end
  end

  describe "Users::RegistrationsController inactive sign-up paths [REQ-FIT-AUTH-002]" do
    it "uses after_inactive_sign_up_path_for when workspace_return_to is stored" do
      controller = Users::RegistrationsController.new
      session = { workspace_return_to: "/taller" }
      allow(controller).to receive(:session).and_return(session)

      expect(controller.send(:after_inactive_sign_up_path_for, nil)).to eq("/taller")
    end

    it "handles inactive sign-up flash and redirect via handle_successful_sign_up" do
      controller = Users::RegistrationsController.new
      controller.request = ActionDispatch::TestRequest.create
      resource = instance_double(
        User,
        id: 1,
        active_for_authentication?: false,
        inactive_message: :unconfirmed
      )

      allow(controller).to receive(:resource).and_return(resource)
      allow(controller).to receive(:session).and_return({ anonymous_session_key: "anon-spec" })
      allow(Analytics::TrackEvent).to receive(:call)
      allow(controller).to receive(:set_flash_message!)
      allow(controller).to receive(:expire_data_after_sign_in!)
      allow(controller).to receive(:respond_with)
      allow(controller).to receive(:after_inactive_sign_up_path_for).with(resource).and_return("/confirmacion-pendiente")

      controller.send(:handle_successful_sign_up)

      expect(controller).to have_received(:set_flash_message!).with(:notice, :"signed_up_but_unconfirmed")
      expect(controller).to have_received(:expire_data_after_sign_in!)
      expect(controller).to have_received(:respond_with).with(resource, location: "/confirmacion-pendiente")
    end
  end

  describe "Billing::Onvo::Config#live? [REQ-FIT-BILL-001]" do
    it "detects live mode" do
      config = Billing::Onvo::Config.new(
        secret_key: "live_secret",
        publishable_key: "live_pub",
        mode: "live",
        webhook_secret: "whsec_live"
      )

      expect(config.live?).to be(true)
      expect(config.test?).to be(false)
    end
  end

  describe "Billing::RegionalPolicy.normalize_country [REQ-FIT-BILL-001]" do
    it "returns nil for blank country codes" do
      expect(Billing::RegionalPolicy.send(:normalize_country, nil)).to be_nil
    end
  end

  describe "Analytics::Thresholds missing config [REQ-FIT-ANALYTICS-001]" do
    after do
      Analytics::Thresholds.send(:remove_instance_variable, :@config) if Analytics::Thresholds.instance_variable_defined?(:@config)
      Analytics::Thresholds.send(:remove_instance_variable, :@last_mtime) if Analytics::Thresholds.instance_variable_defined?(:@last_mtime)
    end

    it "loads an empty hash when the config file is absent" do
      missing = Rails.root.join("tmp/missing-analytics-thresholds-spec.yml")
      stub_const("Analytics::Thresholds::CONFIG_PATH", missing)

      expect(Analytics::Thresholds.send(:load_config)).to eq({})
    end
  end

  describe "NestingPreviewHelper#format_preview_dimension_mm [REQ-FIT-UI-002]" do
    let(:preview_helper) { Class.new { include NestingPreviewHelper }.new }

    it "formats whole and fractional millimeter values" do
      expect(preview_helper.send(:format_preview_dimension_mm, 1200)).to eq("1200")
      expect(preview_helper.send(:format_preview_dimension_mm, 1200.4)).to eq("1200.4")
    end
  end

  describe "CartController#load_pending_cart! [REQ-FIT-BILL-001]" do
    it "clears invalid pending replace payloads from the session" do
      controller = CartController.new
      session = ActionController::TestSession.new(
        pending_cart: { "kind" => "invalid", "currency_mode" => "crc" }
      )
      allow(controller).to receive(:session).and_return(session)

      controller.send(:load_pending_cart!)

      expect(session[:pending_cart]).to be_nil
      expect(controller.instance_variable_get(:@pending_cart)).to be_nil
    end
  end
end
