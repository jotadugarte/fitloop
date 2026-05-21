# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Retained nested DXF after workspace discard", "[REQ-FIT-BILL-003]", type: :service do
  let(:user) { create_billing_user! }
  let(:project) { Project.create!(ephemeral: true, title: "Retain", status: :completed) }
  let(:run) { project.nesting_runs.create!(status: "completed") }

  before do
    project.nested_dxf.attach(
      io: StringIO.new("RETAINED BLOB"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
  end

  it "[REQ-FIT-BILL-003] keeps retained_nested_dxf on grant after ephemeral project is destroyed (D54)" do
    paid_at = Time.current
    grant = DownloadGrant.create!(
      user: user,
      nesting_run: run,
      kind: "single_purchase",
      retained_until: paid_at + Billing::RetainNestedDxf::RETENTION_HOURS.hours
    )
    Billing::RetainNestedDxf.call(grant: grant, nesting_run: run, paid_at: paid_at)

    project.destroy!

    grant.reload
    expect(grant.retained_nested_dxf).to be_attached
    expect(grant.retained_nested_dxf.download).to include("RETAINED BLOB")
    expect(grant.retained_until).to be > Time.current
  end
end
