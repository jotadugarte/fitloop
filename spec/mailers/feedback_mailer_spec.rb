# frozen_string_literal: true

require "rails_helper"

RSpec.describe FeedbackMailer, "[REQ-FIT-OPS-001]" do
  let(:feedback) do
    Feedback.create!(
      feedback_type: "bug",
      message: "El preview no carga en Safari.",
      email: "reporter@example.com",
      status: "pending"
    )
  end

  describe "#admin_notify" do
    it "[REQ-FIT-OPS-001] sends to support inbox with feedback details" do
      mail = described_class.with(feedback: feedback).admin_notify

      expect(mail.to).to eq([ ENV.fetch("FEEDBACK_NOTIFY_EMAIL", "soporte@modusloop.com") ])
      expect(mail.subject).to include(I18n.t("feedback.types.bug"))
      expect(mail.body.encoded).to include("Safari")
    end
  end
end
