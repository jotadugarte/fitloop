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

  def create_active_subscription!(user:, tier_months: 1, starts_at: 1.week.ago, ends_at: 3.weeks.from_now)
    Subscription.create!(
      user: user,
      tier_months: tier_months,
      starts_at: starts_at,
      ends_at: ends_at
    )
  end
end

RSpec.configure do |config|
  config.include BillingModelHelpers, type: :model
  config.include BillingModelHelpers, type: :request
  config.include BillingModelHelpers, type: :service
  config.include BillingModelHelpers, type: :job
end
