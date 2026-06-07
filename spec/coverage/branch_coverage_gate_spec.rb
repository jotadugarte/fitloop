# frozen_string_literal: true

require "rails_helper"

# Final gate: direct branch hits still reported by analyze_coverage.rb after full suite.
RSpec.describe "Branch coverage gate" do
  include BillingModelHelpers
  include Rails.application.routes.url_helpers

  describe Billing::Money, "[REQ-FIT-BILL-001]" do
    it "reuses Currency objects in from_major" do
      currency = Billing::Currency.parse(:usd)

      money = described_class.from_major(BigDecimal("1"), currency)

      expect(money.currency).to eq(currency)
    end
  end

  describe Nesting::SheetStockRow, "[REQ-FIT-NEST-004]" do
    it "assigns nil quantity in initialize" do
      row = described_class.new(width_mm: 500, height_mm: 800, quantity: nil, sort_order: 0)

      expect(row.quantity).to be_nil
    end
  end

  describe Admin::HaciendaSummaryRows, "[REQ-FIT-ADMIN-001]" do
    it "falls back to amount when total_amount is not positive" do
      payment = Payment.new(amount: 99.0, total_amount: 0)

      expect(described_class.net_collected(payment)).to eq(99.0)
    end
  end

  describe Nesting::LocalizedProgressMessage, "[REQ-FIT-JOB-001]" do
    it "returns empty text for blank in-flight progress" do
      project = create_project_for_spec!(title: "Gate blank progress", status: :processing, bind_workspace: false)
      project.update!(progress_message: "")

      expect(described_class.for(project)).to eq("")
    end
  end

  describe Nesting::ProgressSnapshot, "[REQ-FIT-JOB-001]" do
    it "honors explicit message_key values" do
      snapshot = described_class.from_hash(
        { "version" => 1, "phase_id" => "fill", "percent" => 6, "message_key" => "nesting.phase.queued" },
        last_percent: 0
      )

      expect(snapshot.message_key).to eq("nesting.phase.queued")
    end
  end

  describe Nesting::ProgressEta, "[REQ-FIT-JOB-001]" do
    it "returns the deadline when only pieces_total is positive" do
      started = 1.minute.ago

      eta = described_class.estimate(
        started_at: started,
        time_limit_sec: 60,
        pieces_total: 5,
        pieces_placed: 0
      )

      expect(eta).to be_within(1.second).of(started + 60.seconds)
    end
  end

  describe Billing::Onvo::CardInput, "[REQ-FIT-BILL-001]" do
    it "accepts valid holder names and rejects non-test PANs in test mode" do
      allow(ENV).to receive(:fetch).and_call_original
      allow(ENV).to receive(:fetch).with("ONVO_MODE", "test").and_return("test")

      expect do
        described_class.parse!(
          holder_name: "María Rodríguez",
          card_number: "424242424242424242",
          card_exp: "12/30",
          cvv: "123"
        )
      end.to raise_error(ArgumentError, /card_number_test_only/)
    end
  end

  describe Billing::Onvo::ConfirmSinpePayment, "[REQ-FIT-BILL-001]" do
    it "requires a payment and confirms fresh transfers through ONVO" do
      expect do
        described_class.call(payment: nil, identification: "1", mobile_number: "88888888")
      end.to raise_error(ArgumentError, /payment required/)

      payment = Payment.create!(
        user: create_billing_user!,
        nesting_run: create_nesting_run!,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download",
        onvo_payment_intent_id: "pi_gate_fresh"
      )
      client = instance_double(Billing::Onvo::Client)
      allow(client).to receive(:create_payment_method).and_return({ id: "pm_gate" })
      allow(client).to receive(:confirm_payment_intent).and_return({ status: "processing" })

      result = described_class.call(
        payment: payment,
        identification: "123456789",
        mobile_number: "88888888",
        client: client
      )

      expect(result.fetch(:status)).to eq("processing")
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
  end

  describe Nesting::OrphansPresenter::Orphan, "[REQ-FIT-SPLIT-001]" do
    it "returns nil for split_not_feasible? without a proposal" do
      orphan = described_class.new(split_proposal: nil)

      expect(orphan.split_not_feasible?).to be_nil
    end
  end

  describe Nesting::MotherPieceStillPresent, "[REQ-FIT-SPLIT-001]" do
    it "returns false when mother rings cannot be keyed without attachments" do
      project = create_project_for_spec!(title: "Gate mother", bind_workspace: false)
      rings = [ [ [ 0, 0 ], [ 10, 0 ], [ 10, 10 ], [ 0, 10 ] ] ]

      expect(described_class.call(project: project, mother_rings: rings, layer_name: "PIECES")).to be(false)
    end
  end

  describe OrphanResolutionsController, "[REQ-FIT-SPLIT-001]" do
    it "returns early when checkout lock blocks updates" do
      project = create_project_for_spec!(title: "Gate orphan lock", bind_workspace: false)
      host = described_class.new
      host.instance_variable_set(:@project, project)
      allow(host).to receive(:reject_workshop_mutation_if_pending_payment!).and_return(true)
      allow(host).to receive(:redirect_to)

      expect(Nesting::SplitPlanJob).not_to receive(:perform_later)

      host.update
    end

    it "enqueues split planning for system_split resolutions" do
      project = create_project_for_spec!(title: "Gate orphan enqueue", bind_workspace: false)
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

  describe SplitProposalsController, "[REQ-FIT-SPLIT-001]" do
    it "returns early when checkout lock blocks regeneration" do
      project = create_project_for_spec!(title: "Gate split lock", bind_workspace: false)
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
      project = create_project_for_spec!(title: "Gate layers lock", bind_workspace: false)
      host = described_class.new
      host.instance_variable_set(:@project, project)
      allow(host).to receive(:reject_workshop_mutation_if_pending_payment!).and_return(true)
      allow(host).to receive(:redirect_to)

      expect(ProjectLayerSelection).not_to receive(:apply!)

      host.update
    end
  end

  describe Users::SessionsController, "[REQ-FIT-AUTH-002]", type: :request do
    it "skips logout analytics when destroy is called while signed out" do
      allow(Analytics::TrackEvent).to receive(:call)

      delete destroy_user_session_path

      expect(Analytics::TrackEvent).not_to have_received(:call).with("user_logged_out", anything)
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
  end
end
