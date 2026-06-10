# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::DeliverFeedbackJob, "[REQ-FIT-OPS-001]" do
  let(:feedback) do
    Feedback.create!(
      feedback_type: "other",
      message: "Comentario general del taller.",
      email: "other@example.com"
    )
  end

  it "[REQ-FIT-OPS-001] delegates to Notifications::Dispatcher" do
    expect(Notifications::Dispatcher).to receive(:notify_feedback_submitted).with(feedback)

    described_class.perform_now(feedback.id)
  end
end
