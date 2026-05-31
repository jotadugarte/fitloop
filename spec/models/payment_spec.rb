# frozen_string_literal: true

require "rails_helper"

RSpec.describe Payment, "[REQ-FIT-BILL-001]" do
  let(:user) { create_billing_user! }

  describe "associations [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] belongs to user" do
      expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
    end

    it "[REQ-FIT-BILL-001] optionally belongs to nesting_run for single-download payments" do
      expect(described_class.reflect_on_association(:nesting_run).macro).to eq(:belongs_to)
      expect(described_class.reflect_on_association(:nesting_run).options[:optional]).to be(true)
    end
  end

  describe "simulated checkout [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] records succeeded card USD payment with positive amount" do
      payment = described_class.create!(
        user: user,
        status: "succeeded",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2.0,
        purpose: "single_download",
        nesting_run: create_nesting_run!,
        paid_at: Time.current
      )

      expect(payment).to be_persisted
      expect(payment.amount).to be > 0
      expect(payment).to be_succeeded
    end

    it "[REQ-FIT-BILL-001] allows failed status without paid_at" do
      payment = described_class.new(
        user: user,
        status: "failed",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1000,
        purpose: "single_download"
      )

      expect(payment).to be_valid
    end
  end

  describe "ONVO gateway fields [REQ-FIT-BILL-001]" do
    def onvo_payment_attrs(overrides = {})
      {
        user: user,
        status: "pending",
        payment_method: "card_crc",
        currency: "crc",
        amount: 5000,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_test_abc123",
        onvo_mode: "test",
        gateway_status: "requires_payment_method"
      }.merge(overrides)
    end

    it "[REQ-FIT-BILL-001] persists gateway columns for pending ONVO payment without paid_at" do
      payment = described_class.create!(onvo_payment_attrs)

      expect(payment).to be_persisted
      expect(payment.gateway_provider).to eq("onvo")
      expect(payment.onvo_payment_intent_id).to eq("pi_test_abc123")
      expect(payment.onvo_mode).to eq("test")
      expect(payment.gateway_status).to eq("requires_payment_method")
      expect(payment.paid_at).to be_nil
      expect(payment).to be_pending
    end

    it "[REQ-FIT-BILL-001] requires gateway_status succeeded before ONVO payment can be succeeded" do
      payment = described_class.new(
        onvo_payment_attrs(
          status: "succeeded",
          gateway_status: "processing",
          paid_at: Time.current
        )
      )

      expect(payment).not_to be_valid
      expect(payment.errors[:gateway_status]).to be_present
    end

    it "[REQ-FIT-BILL-001] accepts succeeded ONVO payment when gateway_status is succeeded" do
      payment = described_class.new(
        onvo_payment_attrs(
          status: "succeeded",
          gateway_status: "succeeded",
          paid_at: Time.current
        )
      )

      expect(payment).to be_valid
    end

    it "[REQ-FIT-BILL-001] allows legacy succeeded payment without gateway fields (simulate)" do
      payment = described_class.new(
        user: user,
        status: "succeeded",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2.0,
        purpose: "single_download",
        paid_at: Time.current
      )

      expect(payment).to be_valid
      expect(payment.gateway_provider).to be_nil
    end
  end

  describe "purchase_reference [REQ-FIT-BILL-001]" do
    let(:project) { Project.create!(ephemeral: true, title: "Reference spec", status: :completed) }
    let(:run) { project.nesting_runs.create!(status: "completed") }

    it "[REQ-FIT-BILL-001] assigns a 12-digit reference for single_download payments" do
      payment = described_class.create!(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        total_amount: 1130,
        purpose: "single_download"
      )

      expect(payment.purchase_reference).to match(/\A\d{12}\z/)
    end

    it "[REQ-FIT-BILL-001] does not assign reference for plan_subscription payments" do
      payment = described_class.create!(
        user: user,
        status: "pending",
        payment_method: "card_crc",
        currency: "crc",
        amount: 5000,
        total_amount: 5000,
        purpose: "plan_subscription"
      )

      expect(payment.purchase_reference).to be_nil
    end
  end

  describe "#checkout_lock_active? [REQ-FIT-BILL-001]" do
    let(:project) { Project.create!(ephemeral: true, title: "Lock model spec", status: :completed) }
    let(:run) { project.nesting_runs.create!(status: "completed") }

    def pending_payment!(payment_method:, created_at: 5.minutes.ago, **attrs)
      described_class.create!(
        {
          user: user,
          nesting_run: run,
          status: "pending",
          payment_method: payment_method,
          currency: "crc",
          amount: 1130,
          total_amount: 1130,
          purpose: "single_download",
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_lock_#{SecureRandom.hex(4)}",
          onvo_mode: "test",
          gateway_status: "processing",
          created_at: created_at
        }.merge(attrs)
      )
    end

    it "[REQ-FIT-BILL-001] is true for sinpe_crc pending within workshop lock window" do
      payment = pending_payment!(payment_method: "sinpe_crc")

      expect(payment.checkout_lock_active?).to be(true)
    end

    it "[REQ-FIT-BILL-001] is false for card pending within workshop lock window" do
      payment = pending_payment!(payment_method: "card_crc")

      expect(payment.checkout_lock_active?).to be(false)
    end

    it "[REQ-FIT-BILL-001] is false after workshop_lock_minutes elapse" do
      payment = pending_payment!(payment_method: "sinpe_crc", created_at: 16.minutes.ago)

      expect(payment.checkout_lock_active?).to be(false)
    end

    it "[REQ-FIT-BILL-001] is false when checkout_lock_released_at is set" do
      payment = pending_payment!(payment_method: "sinpe_crc", checkout_lock_released_at: 1.minute.ago)

      expect(payment.checkout_lock_active?).to be(false)
    end

    it "[REQ-FIT-BILL-001] is false when checkout_abandoned_at is set" do
      payment = pending_payment!(
        payment_method: "sinpe_crc",
        checkout_abandoned_at: 1.minute.ago,
        checkout_lock_released_at: 1.minute.ago
      )

      expect(payment.checkout_lock_active?).to be(false)
    end

    it "[REQ-FIT-BILL-001] is false when superseded_at is set" do
      payment = pending_payment!(
        payment_method: "sinpe_crc",
        superseded_at: 1.minute.ago,
        checkout_lock_released_at: 1.minute.ago
      )

      expect(payment.checkout_lock_active?).to be(false)
    end

    it "[REQ-FIT-BILL-001] is false when a downloadable grant exists for the nesting run" do
      payment = pending_payment!(payment_method: "sinpe_crc")
      DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: 1.day.from_now
      )

      expect(payment.checkout_lock_active?).to be(false)
    end

    it "[REQ-FIT-BILL-001] stays true with pre-retained grant without retained_until" do
      payment = pending_payment!(payment_method: "sinpe_crc")
      DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: nil
      )

      expect(payment.checkout_lock_active?).to be(true)
    end
  end

  describe "#awaiting_gateway_confirmation? [REQ-FIT-BILL-001]" do
    let(:project) { Project.create!(ephemeral: true, title: "Awaiting gateway spec", status: :completed) }
    let(:run) { project.nesting_runs.create!(status: "completed") }

    def pending_payment!(payment_method:, **attrs)
      described_class.create!(
        {
          user: user,
          nesting_run: run,
          status: "pending",
          payment_method: payment_method,
          currency: "crc",
          amount: 1130,
          total_amount: 1130,
          purpose: "single_download",
          gateway_provider: "onvo",
          onvo_payment_intent_id: "pi_awaiting_#{SecureRandom.hex(4)}",
          onvo_mode: "test",
          gateway_status: "processing"
        }.merge(attrs)
      )
    end

    it "[REQ-FIT-BILL-001] is true for pending SINPE without downloadable grant" do
      payment = pending_payment!(payment_method: "sinpe_crc")

      expect(payment.awaiting_gateway_confirmation?).to be(true)
    end

    it "[REQ-FIT-BILL-001] stays true for abandoned SINPE awaiting late webhook" do
      payment = pending_payment!(
        payment_method: "sinpe_crc",
        checkout_abandoned_at: 1.minute.ago,
        checkout_lock_released_at: 1.minute.ago
      )

      expect(payment.awaiting_gateway_confirmation?).to be(true)
    end

    it "[REQ-FIT-BILL-001] is false for abandoned card checkout after 3DS cancel" do
      payment = pending_payment!(
        payment_method: "card_crc",
        gateway_status: "requires_payment_method",
        checkout_abandoned_at: 1.minute.ago,
        checkout_lock_reason: Billing::CheckoutLockReason::USER_CANCELED_3DS
      )

      expect(payment.awaiting_gateway_confirmation?).to be(false)
    end

    it "[REQ-FIT-BILL-001] is false when superseded or grant is downloadable" do
      payment = pending_payment!(payment_method: "sinpe_crc", superseded_at: 1.minute.ago)

      expect(payment.awaiting_gateway_confirmation?).to be(false)

      active = pending_payment!(payment_method: "sinpe_crc")
      DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: 1.day.from_now
      )

      expect(active.awaiting_gateway_confirmation?).to be(false)
    end
  end

  describe "checkout_lock_reason [REQ-FIT-BILL-001]" do
    let(:project) { Project.create!(ephemeral: true, title: "Lock reason spec", status: :completed) }
    let(:run) { project.nesting_runs.create!(status: "completed") }

    it "[REQ-FIT-BILL-001] accepts known checkout_lock_reason values" do
      payment = described_class.new(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        checkout_lock_reason: Billing::CheckoutLockReason::USER_ABANDONED
      )

      expect(payment).to be_valid
    end

    it "[REQ-FIT-BILL-001] rejects unknown checkout_lock_reason values" do
      payment = described_class.new(
        user: user,
        nesting_run: run,
        status: "pending",
        payment_method: "sinpe_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        checkout_lock_reason: "bogus"
      )

      expect(payment).not_to be_valid
      expect(payment.errors[:checkout_lock_reason]).to be_present
    end
  end

  describe "payment snapshot fields [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] persists purchaser and amount breakdown for succeeded and failed payments (D20, D24)" do
      payment = described_class.create!(
        user: user,
        status: "failed",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2.5,
        purpose: "single_download",
        purchaser_name: "Ada Lovelace",
        purchaser_email: "ada@example.com",
        product_description: "Descarga única",
        list_price: 2.5,
        discount_amount: 0.5,
        subtotal: 2.5,
        tax_amount: 0.0,
        total_amount: 2.0
      )

      expect(payment.purchaser_name).to eq("Ada Lovelace")
      expect(payment.purchaser_email).to eq("ada@example.com")
      expect(payment.product_description).to eq("Descarga única")
      expect(payment.total_amount).to eq(2.0)
    end
  end

  describe "cabys_code validation and assignment" do
    it "automatically assigns the default CAByS code to a new payment on creation" do
      payment = described_class.create!(
        user: user,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2.5,
        purpose: "single_download"
      )
      expect(payment.cabys_code).to eq(Payment::DEFAULT_CABYS_CODE)
    end

    it "validates that cabys_code matches DEFAULT_CABYS_CODE" do
      payment = described_class.new(
        user: user,
        status: "pending",
        payment_method: "card_usd",
        currency: "usd",
        amount: 2.5,
        purpose: "single_download",
        cabys_code: "invalid_code"
      )
      expect(payment).not_to be_valid
      expect(payment.errors[:cabys_code]).to be_present
    end
  end

  describe "#incomplete_card_checkout_attempt? [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] is true for failed card attempt superseded by a later success on the same run" do
      run = create_nesting_run!
      first = described_class.create!(
        user: user,
        nesting_run: run,
        status: "failed",
        payment_method: "card_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_first",
        onvo_mode: "test",
        gateway_status: "failed",
        created_at: 2.minutes.ago
      )
      described_class.create!(
        user: user,
        nesting_run: run,
        status: "succeeded",
        payment_method: "card_crc",
        currency: "crc",
        amount: 1130,
        purpose: "single_download",
        paid_at: Time.current,
        gateway_provider: "onvo",
        onvo_payment_intent_id: "pi_second",
        onvo_mode: "test",
        gateway_status: "succeeded",
        created_at: 1.minute.ago
      )
      DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: 1.day.from_now
      )

      expect(first.incomplete_card_checkout_attempt?).to be(true)
    end
  end
end
