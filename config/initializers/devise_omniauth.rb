# frozen_string_literal: true

Devise.setup do |config|
  google_id = ENV["GOOGLE_OAUTH_CLIENT_ID"].presence
  google_secret = ENV["GOOGLE_OAUTH_CLIENT_SECRET"].presence
  if google_id && google_secret
    config.omniauth :google_oauth2, google_id, google_secret, scope: "email, profile"
  elsif Rails.env.test? || Rails.env.development?
    config.omniauth :google_oauth2, "dev-google-client-id", "dev-google-client-secret",
                    provider_ignores_state: true
  end

  facebook_id = ENV["FACEBOOK_APP_ID"].presence
  facebook_secret = ENV["FACEBOOK_APP_SECRET"].presence
  if facebook_id && facebook_secret
    config.omniauth :facebook, facebook_id, facebook_secret
  elsif Rails.env.test?
    config.omniauth :facebook, "test-facebook-app-id", "test-facebook-app-secret",
                    provider_ignores_state: true
  end

  apple_id = ENV["APPLE_CLIENT_ID"].presence
  apple_secret = ENV["APPLE_CLIENT_SECRET"].presence
  if apple_id && apple_secret
    config.omniauth :apple, apple_id, apple_secret
  elsif Rails.env.test?
    config.omniauth :apple, "test-apple-client-id", "test-apple-client-secret",
                    provider_ignores_state: true
  end
end
