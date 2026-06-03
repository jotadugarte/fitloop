# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Cart persistence across login", "[REQ-FIT-BILL-001]", type: :request do
  def create_confirmed_user!(email: "cart-persist@example.com")
    User.new(
      email: email,
      password: "securepassword12",
      password_confirmation: "securepassword12",
      name: "Cart Persist",
      terms_accepted_at: Time.current,
      terms_version: "v1-placeholder",
      time_zone: "America/Costa_Rica",
      confirmed_at: Time.current
    ).tap(&:skip_confirmation_notification!).tap(&:save!)
  end

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  it "[REQ-FIT-BILL-001] stores guest cart token in session and merges on login (D6, D15)" do
    project = begin_workspace_session!
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)

    post cart_path, params: { kind: "single_download", nesting_run_id: run.id, currency_mode: "crc" }
    expect(response).to have_http_status(:found)

    guest_token = session.fetch(:cart_guest_token)
    guest_cart = Cart.find_by(guest_token: guest_token)
    expect(guest_cart).to be_present
    expect(guest_cart.user_id).to be_nil

    delete destroy_user_session_path

    user = create_confirmed_user!
    sign_in_user! user
    expect(response).to have_http_status(:found)

    expect(Cart.find_by(guest_token: guest_token)).to be_nil
    expect(Cart.find_by(user_id: user.id)).to be_present
  end
end
