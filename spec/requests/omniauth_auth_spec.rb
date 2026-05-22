# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OmniAuth sign-in UI", "[REQ-FIT-AUTH-002]", type: :request do
  PROVIDER_TEST_IDS = %w[oauth-google oauth-facebook oauth-apple oauth-email].freeze

  def position_of(body, test_id)
    body.index("data-testid=\"#{test_id}\"")
  end

  def expect_provider_order!(body)
    google = position_of(body, "oauth-google")
    facebook = position_of(body, "oauth-facebook")
    apple = position_of(body, "oauth-apple")
    email = position_of(body, "oauth-email")

    expect(google).to be_present
    expect(facebook).to be_present
    expect(apple).to be_present
    expect(email).to be_present
    expect(google).to be < facebook
    expect(facebook).to be < apple
    expect(apple).to be < email
  end

  def with_google_credentials
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_OAUTH_CLIENT_ID").and_return("test-google-client-id")
    allow(ENV).to receive(:[]).with("GOOGLE_OAUTH_CLIENT_SECRET").and_return("test-google-client-secret")
    yield
  end

  def without_google_credentials
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("GOOGLE_OAUTH_CLIENT_ID").and_return(nil)
    allow(ENV).to receive(:[]).with("GOOGLE_OAUTH_CLIENT_SECRET").and_return(nil)
    yield
  end

  shared_examples "ordered OAuth and email UI" do |path_name|
    it "[REQ-FIT-AUTH-002] renders providers Google → Facebook → Apple → email on #{path_name}" do
      with_google_credentials do
        get send(path_name)

        expect(response).to have_http_status(:ok)
        expect(response.body).to include('data-testid="auth-back"')
        expect(response.body).to include('data-testid="auth-page"')
        expect_provider_order!(response.body)
      end
    end

    it "[REQ-FIT-AUTH-002] omits Google on #{path_name} in production without credentials" do
      without_google_credentials do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

        get send(path_name)

        expect(response).to have_http_status(:ok)
        expect(response.body).not_to include('data-testid="oauth-google"')
        expect(response.body).to include('data-testid="oauth-facebook"')
        expect(response.body).to include('data-testid="oauth-apple"')
        expect(response.body).to include('data-testid="oauth-email"')
      end
    end

    it "[REQ-FIT-AUTH-002] links Google to OmniAuth when configured on #{path_name}" do
      with_google_credentials do
        get send(path_name)

        expect(response.body).to match(%r{action="/auth/google_oauth2"|href="/users/auth/google_oauth2"|href="/auth/google_oauth2"})
      end
    end
  end

  describe "GET /iniciar-sesion [REQ-FIT-AUTH-002]" do
    include_examples "ordered OAuth and email UI", :new_user_session_path
  end

  describe "GET /crear-cuenta [REQ-FIT-AUTH-002]" do
    include_examples "ordered OAuth and email UI", :new_user_registration_path
  end
end
