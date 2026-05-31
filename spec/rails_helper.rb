# frozen_string_literal: true

require "spec_helper"
ENV["RAILS_ENV"] ||= "test"

# Load .env before Rails (PGUSER/PGPASSWORD for WSL PostgreSQL over TCP).
require "dotenv/load"

require_relative "../config/environment"

# Isolate test billing from developer .env (ONVO keys). ONVO request specs override per example.
ENV["BILLING_GATEWAY"] = Billing::Gateway::SIMULATE

abort("The Rails environment is running in production mode!") if Rails.env.production?
require "rspec/rails"

Dir[Rails.root.join("spec/support/**/*.rb")].sort.each { |f| require f }

RSpec.configure do |config|
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include ActionDispatch::TestProcess::FixtureFile
  config.use_transactional_fixtures = true
  config.infer_spec_type_from_file_location!
  config.filter_rails_from_backtrace!

  config.before(:each, type: :system) do
    driven_by :rack_test
  end
end
