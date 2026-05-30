# frozen_string_literal: true

require "rails_helper"

RSpec.describe DownloadGrant, "[REQ-FIT-BILL-003]" do
  let(:user) { create_billing_user! }
  let(:nesting_run) { create_nesting_run! }

  describe "associations [REQ-FIT-BILL-003]" do
    it "[REQ-FIT-BILL-003] belongs to user and optionally to nesting_run (D54)" do
      expect(described_class.reflect_on_association(:user).macro).to eq(:belongs_to)
      expect(described_class.reflect_on_association(:nesting_run).macro).to eq(:belongs_to)
      expect(described_class.reflect_on_association(:nesting_run).options[:optional]).to be(true)
    end

    it "[REQ-FIT-BILL-003] has retained_nested_dxf attachment for single purchase (D54)" do
      expect(described_class.new).to respond_to(:retained_nested_dxf)
      expect(described_class.reflect_on_attachment(:retained_nested_dxf)).to be_present
    end
  end

  describe "grant kinds [REQ-FIT-BILL-003]" do
    it "[REQ-FIT-BILL-003] supports single_purchase and plan_included kinds" do
      expect(described_class.kinds.keys).to contain_exactly("single_purchase", "plan_included")
    end

    it "[REQ-FIT-BILL-003] enforces one grant per user and nesting_run" do
      described_class.create!(
        user: user,
        nesting_run: nesting_run,
        kind: "single_purchase",
        retained_until: 24.hours.from_now
      )
      duplicate = described_class.new(user: user, nesting_run: nesting_run, kind: "plan_included")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors).to be_of_kind(:nesting_run_id, :taken)
    end

    it "[REQ-FIT-BILL-003] requires retained_until for single_purchase grants (D54)" do
      grant = described_class.new(user: user, nesting_run: nesting_run, kind: "single_purchase")

      expect(grant).not_to be_valid
      expect(grant.errors).to be_of_kind(:retained_until, :blank)
    end

    it "[REQ-FIT-BILL-003] allows plan_included without retained_until" do
      grant = described_class.create!(
        user: user,
        nesting_run: nesting_run,
        kind: "plan_included",
        retained_until: nil
      )

      expect(grant).to be_persisted
      expect(grant.retained_until).to be_nil
    end
  end

  describe "single_purchase pre-retention staging [REQ-FIT-BILL-001] [REQ-FIT-BILL-003]" do
    it "[REQ-FIT-BILL-001] allows single_purchase without retained_until while staging pre-retention" do
      grant = described_class.new(
        user: user,
        nesting_run: nesting_run,
        kind: "single_purchase",
        retained_until: nil
      )

      expect(grant).to be_valid
      expect(grant.retention_active?).to be(false)
    end

    it "[REQ-FIT-BILL-001] persists staging grant without retained_until" do
      grant = described_class.create!(
        user: user,
        nesting_run: nesting_run,
        kind: "single_purchase",
        retained_until: nil
      )

      expect(grant).to be_persisted
      expect(grant.retained_until).to be_nil
      expect(grant.retention_active?).to be(false)
    end

    it "[REQ-FIT-BILL-003] requires retained_until when retention is committed" do
      grant = described_class.new(
        user: user,
        nesting_run: nesting_run,
        kind: "single_purchase",
        retained_until: nil
      )
      grant.retention_committed = true

      expect(grant).not_to be_valid
      expect(grant.errors).to be_of_kind(:retained_until, :blank)
    end

    it "[REQ-FIT-BILL-003] keeps fulfilled single_purchase valid with retained_until in the future" do
      grant = described_class.create!(
        user: user,
        nesting_run: nesting_run,
        kind: "single_purchase",
        retained_until: 1.day.from_now
      )

      expect(grant).to be_valid
      expect(grant.retention_active?).to be(true)
    end
  end
end
