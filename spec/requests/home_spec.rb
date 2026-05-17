# frozen_string_literal: true

# Request spec — runs after Rails scaffold (bundle exec rspec spec/requests/home_spec.rb).
require "rails_helper"

RSpec.describe "Home", type: :request do
  # Home#index does not use Active Record; avoid opening a test DB transaction.
  self.use_transactional_tests = false

  describe "GET /" do
    it "[REQ-FIT-APP-001] returns Fitloop home with 200" do
      get root_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Fitloop")
    end

    it "[REQ-FIT-APP-001] renders app logo from images/" do
      get root_path

      expect(response.body).to match(%r{images/}i)
    end
  end
end
