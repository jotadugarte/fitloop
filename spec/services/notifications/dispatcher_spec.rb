# frozen_string_literal: true

require "rails_helper"

RSpec.describe Notifications::Dispatcher, "[REQ-FIT-OPS-001]" do
  include ActiveJob::TestHelper

  let(:feedback) do
    Feedback.create!(
      feedback_type: "suggestion",
      message: "Integrar atajos de teclado.",
      email: "idea@example.com"
    )
  end

  around do |example|
    previous_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = previous_adapter
  end

  describe ".notify_feedback_submitted" do
    it "[REQ-FIT-OPS-001] enqueues admin email delivery" do
      allow(described_class).to receive(:discord_webhook_configured?).and_return(false)

      expect do
        described_class.notify_feedback_submitted(feedback)
      end.to have_enqueued_job(ActionMailer::MailDeliveryJob)
    end

    it "[REQ-FIT-OPS-001] delivers Discord embed when webhook is configured" do
      allow(described_class).to receive(:discord_webhook_configured?).and_return(true)
      expect(described_class).to receive(:deliver_discord_embed).with(feedback).and_return(true)

      described_class.notify_feedback_submitted(feedback)
    end

    it "[REQ-FIT-OPS-001] raises when feedback is not persisted" do
      expect { described_class.notify_feedback_submitted(Feedback.new) }.to raise_error(ArgumentError, /precondition/)
    end
  end

  describe ".deliver_discord_embed" do
    it "[REQ-FIT-OPS-001] posts embed payload when webhook URL is configured" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DISCORD_WEBHOOK_URL").and_return("https://discord.test/webhook")

      http = instance_double(Net::HTTP)
      response = instance_double(Net::HTTPSuccess)
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(true)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(response)

      feedback.guest_metadata = { "ip" => "203.0.113.10" }
      feedback.source_url = "https://example.com/taller"

      expect(described_class.deliver_discord_embed(feedback)).to be(true)
    end

    it "[REQ-FIT-OPS-001] skips HTTP when webhook URL is absent" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DISCORD_WEBHOOK_URL").and_return("")

      expect(Net::HTTP).not_to receive(:new)
      expect(described_class.deliver_discord_embed(feedback)).to be(false)
    end

    it "[REQ-FIT-OPS-001] raises when Discord webhook responds with failure" do
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("DISCORD_WEBHOOK_URL").and_return("https://discord.test/webhook")

      http = instance_double(Net::HTTP)
      response = instance_double(Net::HTTPBadRequest)
      allow(response).to receive(:is_a?).with(Net::HTTPSuccess).and_return(false)
      allow(Net::HTTP).to receive(:new).and_return(http)
      allow(http).to receive(:use_ssl=)
      allow(http).to receive(:open_timeout=)
      allow(http).to receive(:read_timeout=)
      allow(http).to receive(:request).and_return(response)

      expect { described_class.deliver_discord_embed(feedback) }.to raise_error(ArgumentError, /postcondition/)
    end
  end
end
