# frozen_string_literal: true

if ENV["HONEYBADGER_API_KEY"].present?
  Honeybadger.configure do |config|
    config.api_key = ENV["HONEYBADGER_API_KEY"]
    config.report_data = true
    config.breadcrumbs.enabled = true
  end
end
