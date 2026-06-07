# frozen_string_literal: true

require "rails_helper"

RSpec.describe MisPagos::DownloadsController, "[REQ-FIT-BILL-003]" do
  include BillingModelHelpers

  it "records nil project_id when the grant has no nesting run" do
    user = create_billing_user!
    grant = DownloadGrant.create!(
      user: user,
      nesting_run: nil,
      kind: "single_purchase",
      retained_until: 1.day.from_now
    )
    grant.retained_nested_dxf.attach(
      io: StringIO.new("nested"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )

    host = described_class.new
    host.request = ActionDispatch::TestRequest.create
    host.response = ActionDispatch::TestResponse.new
    host.instance_variable_set(:@grant, grant)
    allow(host).to receive(:current_user).and_return(user)
    allow(host).to receive(:session).and_return({})
    allow(Billing::RetainedDownload).to receive(:serve!).and_return(
      data: "nested",
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    allow(Analytics::TrackEvent).to receive(:call)
    allow(host).to receive(:send_data)

    host.show

    expect(Analytics::TrackEvent).to have_received(:call).with(
      "download_completed",
      hash_including(project_id: nil, nesting_run_id: nil)
    )
  end
end
