# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PreRetainNestedDxf, "[REQ-FIT-BILL-001] [REQ-FIT-BILL-003]", type: :service do
  let(:user) { create_billing_user! }
  let(:project) { Project.create!(ephemeral: true, title: "Pre-retain spec", status: :completed) }
  let(:run) { project.nesting_runs.create!(status: "completed") }

  before do
    project.nested_dxf.attach(
      io: StringIO.new("PRE-RETAINED BLOB"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
  end

  describe ".call [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] copies nested_dxf to grant with retained_until nil" do
      grant = described_class.call(user: user, nesting_run: run)

      expect(grant).to be_persisted
      expect(grant).to be_single_purchase
      expect(grant.user_id).to eq(user.id)
      expect(grant.nesting_run_id).to eq(run.id)
      expect(grant.retained_until).to be_nil
      expect(grant.retention_active?).to be(false)
      expect(grant.retained_nested_dxf).to be_attached
      expect(grant.retained_nested_dxf.download).to include("PRE-RETAINED BLOB")
    end

    it "[REQ-FIT-BILL-001] find_or_initialize updates an existing staging grant for the same run" do
      existing = DownloadGrant.create!(
        user: user,
        nesting_run: run,
        kind: "single_purchase",
        retained_until: nil
      )

      grant = described_class.call(user: user, nesting_run: run)

      expect(grant.id).to eq(existing.id)
      expect(DownloadGrant.where(user_id: user.id, nesting_run_id: run.id).count).to eq(1)
      expect(grant.retained_nested_dxf).to be_attached
    end

    it "[REQ-FIT-BILL-001] raises when project nested_dxf is missing" do
      bare_project = Project.create!(ephemeral: true, title: "No DXF", status: :completed)
      bare_run = bare_project.nesting_runs.create!(status: "completed")

      expect do
        described_class.call(user: user, nesting_run: bare_run)
      end.to raise_error(ArgumentError, /nested_dxf missing/)
    end
  end
end
