# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Anonymous session merging on auth", "[REQ-FIT-ANALYTICS-001]", type: :request do
  let(:user) { create_billing_user!(email: "designer@example.com") }

  before do
    allow_any_instance_of(User).to receive(:send_on_create_confirmation_instructions)
  end

  it "automatically merges anonymous events to user_id on login" do
    # 1. Visit root to initialize session and retrieve anonymous session key
    get root_path
    anon_key = session[:anonymous_session_key]
    expect(anon_key).to be_present

    # 2. Create some anonymous events under this key
    UserEvent.create!(
      event_type: "workspace_started",
      priority: "low",
      anonymous_session_key: anon_key,
      user_id: nil,
      occurred_at: Time.current - 5.minutes
    )
    UserEvent.create!(
      event_type: "first_dxf_uploaded",
      priority: "low",
      anonymous_session_key: anon_key,
      user_id: nil,
      occurred_at: Time.current
    )

    # 3. Log in
    post user_session_path,
         params: { user: { email: user.email, password: "securepassword12" } }

    expect(response).to redirect_to(root_path) # Redirects to home/root or dashboard

    # 4. Verify events have been merged to user.id
    events = UserEvent.where(anonymous_session_key: anon_key)
    expect(events.count).to eq(2)
    expect(events.pluck(:user_id)).to all(eq(user.id))
  end
end
