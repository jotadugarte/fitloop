# frozen_string_literal: true

module Auth
  # [REQ-FIT-AUTH-002] OAuth buttons: Google only when ENV credentials exist; Facebook/Apple always in UI.
  class OmniauthProviders
    Provider = Data.define(:key, :test_id, :client_id_env, :client_secret_env)

    OAUTH = [
      Provider.new(:google_oauth2, "oauth-google", "GOOGLE_OAUTH_CLIENT_ID", "GOOGLE_OAUTH_CLIENT_SECRET"),
      Provider.new(:facebook, "oauth-facebook", "FACEBOOK_APP_ID", "FACEBOOK_APP_SECRET"),
      Provider.new(:apple, "oauth-apple", "APPLE_CLIENT_ID", "APPLE_CLIENT_SECRET")
    ].freeze

    def self.for_ui
      ordered = []
      google = OAUTH.find { |p| p.key == :google_oauth2 }
      ordered << google if credentials_present?(google)
      ordered.concat(OAUTH.reject { |p| p.key == :google_oauth2 })
      ordered
    end

    def self.credentials_present?(provider)
      precondition!(provider.is_a?(Provider))
      ENV[provider.client_id_env].present? && ENV[provider.client_secret_env].present?
    end

    def self.precondition!(condition)
      raise ArgumentError, "precondition failed" unless condition
    end
    private_class_method :precondition!
  end
end
