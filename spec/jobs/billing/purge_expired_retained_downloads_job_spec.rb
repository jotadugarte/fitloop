# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::PurgeExpiredRetainedDownloadsJob, "[REQ-FIT-BILL-003]", type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create_billing_user! }
  let(:run) { create_nesting_run! }

  it "[REQ-FIT-BILL-003] purges retained_nested_dxf after retained_until (D56)" do
    grant = DownloadGrant.create!(
      user: user,
      nesting_run: run,
      kind: "single_purchase",
      retained_until: 1.hour.ago
    )
    grant.retained_nested_dxf.attach(
      io: StringIO.new("OLD"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )

    described_class.perform_now

    expect(grant.reload.retained_nested_dxf).not_to be_attached
  end
end
