# frozen_string_literal: true

require "rails_helper"

RSpec.describe "OAuth removal", "[REQ-FIT-AUTH-002]", type: :request do
  describe "GET /users/sign_in" do
    it "does not render Google, Facebook, or Apple buttons, nor oauth-providers elements" do
      get new_user_session_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Google")
      expect(response.body).not_to include("Facebook")
      expect(response.body).not_to include("Apple")
      expect(response.body).not_to include("oauth-providers")
    end
  end

  describe "GET /users/sign_up" do
    it "does not render Google, Facebook, or Apple buttons, nor oauth-providers elements" do
      get new_user_registration_path

      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("Google")
      expect(response.body).not_to include("Facebook")
      expect(response.body).not_to include("Apple")
      expect(response.body).not_to include("oauth-providers")
    end
  end

  describe "OmniAuth routing" do
    it "does not route to google_oauth2" do
      get "/users/auth/google_oauth2"
      expect(response).to have_http_status(:not_found)
    end

    it "does not route to facebook" do
      get "/users/auth/facebook"
      expect(response).to have_http_status(:not_found)
    end

    it "does not route to apple" do
      get "/users/auth/apple"
      expect(response).to have_http_status(:not_found)
    end
  end
end
