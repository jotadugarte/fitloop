# frozen_string_literal: true

require "rails_helper"

RSpec.describe "ONVO checkout UI", "[REQ-FIT-BILL-001]", type: :request do
  let(:user) { create_billing_user! }
  let!(:checkout_context) { prepare_single_download! }
  let(:run) { checkout_context[:run] }

  around do |example|
    keys = %w[BILLING_GATEWAY ONVO_PUBLISHABLE_KEY]
    previous = keys.index_with { |key| ENV[key] }
    ENV["BILLING_GATEWAY"] = "onvo"
    ENV["ONVO_PUBLISHABLE_KEY"] = "onvo_test_publishable_ui"
    example.run
  ensure
    previous.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  before { sign_in_user! user }

  def sign_in_user!(user)
    post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }
  end

  def prepare_single_download!
    project = begin_workspace_session!
    run = project.nesting_runs.create!(status: "completed")
    project.update!(status: :completed)
    project.nested_dxf.attach(
      io: StringIO.new("NESTED"),
      filename: "nested.dxf",
      content_type: "application/dxf"
    )
    { project: project, run: run }
  end

  describe "GET /checkout [REQ-FIT-BILL-001]" do
    it "[REQ-FIT-BILL-001] renders ONVO checkout shell with card-only fields for card methods" do
      get checkout_path(nesting_run_id: run.id, payment_method: "card_crc", locale: "es"),
          headers: { "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-controller="onvo-checkout"')
      expect(response.body).to include('data-testid="onvo-card-fields"')
      expect(response.body).to include('name="card_number"')
      expect(response.body).not_to include('data-testid="onvo-sdk-container"')
      expect(response.body).to match(/data-testid="onvo-sinpe-panel"[^>]*\shidden/)
    end

    it "[REQ-FIT-BILL-001] renders SINPE identification fields when sinpe_crc is selected" do
      get checkout_path(nesting_run_id: run.id, payment_method: "sinpe_crc", locale: "es"),
          headers: { "CF-IPCountry" => "CR" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-testid="onvo-sinpe-fields"')
      expect(response.body).to include('data-testid="onvo-sinpe-how"')
      expect(response.body).to include(I18n.t("billing.checkout.onvo.sinpe_how_title", locale: :es))
      expect(response.body).to match(/data-testid="onvo-card-panel"[^>]*\shidden/)
      expect(response.body).to include('name="sinpe_identification"')
      expect(response.body).to include('name="sinpe_mobile_number"')
      expect(response.body).to include(I18n.t("billing.checkout.onvo.sinpe_destination_name", locale: :es))
      expect(response.body).to include('data-onvo-checkout-target="secondaryActions"')
      expect(response.body).not_to include('data-onvo-checkout-target="sinpeContinueButton"')
    end
  end
end
