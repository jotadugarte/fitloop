# frozen_string_literal: true

require "rails_helper"

RSpec.describe Billing::DownloadToken, "[REQ-FIT-BILL-003]", type: :service do
  include ActiveSupport::Testing::TimeHelpers

  let(:user) { create_billing_user! }
  let(:nesting_run) { create_nesting_run! }

  it "[REQ-FIT-BILL-003] issues a verifiable token for user and nesting run (D45)" do
    token = described_class.issue(user: user, nesting_run: nesting_run)
    payload = described_class.verify(token)

    expect(payload[:user_id]).to eq(user.id)
    expect(payload[:nesting_run_id]).to eq(nesting_run.id)
  end

  it "[REQ-FIT-BILL-003] rejects expired tokens" do
    token = described_class.issue(user: user, nesting_run: nesting_run)

    travel_to(Billing::DownloadToken::TTL.from_now + 1.second) do
      expect { described_class.verify(token) }.to raise_error(described_class::InvalidToken)
    end
  end
end
