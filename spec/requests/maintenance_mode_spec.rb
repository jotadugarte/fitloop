# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Maintenance Mode", type: :request do
  let(:user) { create_billing_user!(email: "user@example.com") }
  let(:admin_user) { create_billing_user!(email: "admin@example.com").tap { |u| u.update!(admin: true) } }

  context "when MAINTENANCE_MODE is false or unset" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MAINTENANCE_MODE").and_return(nil)
    end

    it "renders the home page successfully" do
      get "/"
      expect(response.status).to eq(200)
    end
  end

  context "when MAINTENANCE_MODE is true" do
    before do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("MAINTENANCE_MODE").and_return("true")
    end

    it "renders the maintenance page for non-logged in users on root path" do
      get "/"
      expect(response.status).to eq(503)
      expect(response.body).to include(I18n.t("maintenance.title"))
    end

    it "renders the maintenance page for non-admin logged in users" do
      sign_in user
      get "/"
      expect(response.status).to eq(503)
      expect(response.body).to include(I18n.t("maintenance.title"))
    end

    it "bypasses maintenance mode for logged in admin users" do
      sign_in admin_user
      get "/"
      expect(response.status).to eq(200)
    end

    it "bypasses maintenance mode for health check endpoint (/up)" do
      get "/up"
      expect(response.status).to eq(200)
    end

    it "bypasses maintenance mode for Devise routes starting with /iniciar-sesion" do
      get "/iniciar-sesion"
      expect(response.status).to eq(200)
    end

    it "bypasses maintenance mode for Devise sign out path" do
      delete "/cerrar-sesion"
      expect(response.status).not_to eq(503)
    end

    it "bypasses maintenance mode for asset requests" do
      get "/assets/application.css"
      expect(response.status).not_to eq(503)
    end
  end
end
