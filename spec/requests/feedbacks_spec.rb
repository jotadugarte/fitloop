# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Feedbacks", "[REQ-FIT-OPS-001]", type: :request do
  around do |example|
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = previous_adapter
  end

  describe "POST /feedbacks" do
    it "[REQ-FIT-OPS-001] creates anonymous feedback and enqueues notification delivery" do
      expect do
        post feedbacks_path,
             params: {
               feedback: {
                 feedback_type: "suggestion",
                 email: "guest@example.com",
                 message: "Me gustaría exportar PDF.",
                 source_url: "https://example.com/taller"
               }
             },
             headers: { "HTTP_USER_AGENT" => "RSpec Agent", "REMOTE_ADDR" => "203.0.113.10" },
             as: :turbo_stream
      end.to change(Feedback, :count).by(1)
        .and have_enqueued_job(Notifications::DeliverFeedbackJob)

      expect(response).to have_http_status(:ok)
      feedback = Feedback.last
      expect(feedback.guest_metadata["ip"]).to eq("203.0.113.10")
      expect(feedback.guest_metadata["user_agent"]).to eq("RSpec Agent")
    end

    it "[REQ-FIT-OPS-001] creates authenticated feedback without guest email" do
      user = create_billing_user!(email: "signed-in@example.com")
      post user_session_path, params: { user: { email: user.email, password: "securepassword12" } }

      expect do
        post feedbacks_path,
             params: {
               feedback: {
                 feedback_type: "bug",
                 message: "Encontré un error en el preview."
               }
             },
             as: :turbo_stream
      end.to change(Feedback, :count).by(1)

      feedback = Feedback.last
      expect(feedback.user).to eq(user)
      expect(feedback.email).to be_nil
    end

    it "[REQ-FIT-OPS-001] returns unprocessable content for invalid payload" do
      post feedbacks_path,
           params: { feedback: { feedback_type: "bug", email: "bad", message: "hola" } },
           as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("feedback-dialog-errors")
    end

    it "[REQ-FIT-OPS-001] redirects HTML clients with an error flash on invalid payload" do
      post feedbacks_path,
           params: { feedback: { feedback_type: "bug", email: "bad", message: "hola" } }

      expect(response).to redirect_to(root_path)
      expect(flash[:alert]).to eq(I18n.t("feedback.flash.error"))
    end
  end
end
