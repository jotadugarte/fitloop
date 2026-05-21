# frozen_string_literal: true

module BillingModelHelpers
  def create_billing_user!(email: "billing@example.com")
    User.new(
      email: email,
      password: "securepassword12",
      password_confirmation: "securepassword12",
      name: "Billing User",
      terms_accepted_at: Time.current,
      terms_version: "v1-placeholder",
      time_zone: "America/Costa_Rica",
      confirmed_at: Time.current
    ).tap(&:skip_confirmation_notification!).tap(&:save!)
  end

  def create_nesting_run!
    project = Project.create!(ephemeral: true, title: "Billing nest", status: :draft)
    project.nesting_runs.create!(status: "completed")
  end
end

RSpec.configure do |config|
  config.include BillingModelHelpers, type: :model
end
