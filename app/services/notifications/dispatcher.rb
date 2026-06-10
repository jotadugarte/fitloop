# frozen_string_literal: true

module Notifications
  # [REQ-FIT-OPS-001] Delivers feedback notifications to email and Discord webhook.
  class Dispatcher
    DISCORD_COLORS = {
      "bug" => 0xE03E3E,
      "suggestion" => 0x3E7BE0,
      "other" => 0x808080
    }.freeze

    HTTP_OPEN_TIMEOUT_SEC = 5
    HTTP_READ_TIMEOUT_SEC = 10

    def self.notify_feedback_submitted(feedback)
      precondition!(feedback.is_a?(Feedback) && feedback.persisted?)

      FeedbackMailer.with(feedback: feedback).admin_notify.deliver_later
      deliver_discord_embed(feedback) if discord_webhook_configured?

      postcondition!(true)
    end

    def self.deliver_discord_embed(feedback)
      precondition!(feedback.is_a?(Feedback) && feedback.persisted?)

      webhook_url = ENV["DISCORD_WEBHOOK_URL"].to_s.strip
      return false if webhook_url.blank?

      uri = URI(webhook_url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = HTTP_OPEN_TIMEOUT_SEC
      http.read_timeout = HTTP_READ_TIMEOUT_SEC

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"] = "application/json"
      request.body = discord_payload(feedback).to_json

      response = http.request(request)
      postcondition!(response.is_a?(Net::HTTPSuccess))
      response.is_a?(Net::HTTPSuccess)
    end

    def self.discord_webhook_configured?
      ENV["DISCORD_WEBHOOK_URL"].to_s.strip.present?
    end

    def self.discord_payload(feedback)
      color = DISCORD_COLORS.fetch(feedback.feedback_type, DISCORD_COLORS["other"])
      type_label = I18n.t("feedback.types.#{feedback.feedback_type}", default: feedback.feedback_type)

      {
        embeds: [
          {
            title: "Nuevo feedback: #{type_label}",
            description: feedback.message.truncate(4000),
            color: color,
            fields: discord_fields(feedback)
          }
        ]
      }
    end

    def self.discord_fields(feedback)
      fields = [
        { name: "Correo", value: feedback.submitter_email.to_s.truncate(256), inline: true },
        { name: "Estado", value: feedback.status, inline: true }
      ]

      if feedback.source_url.present?
        fields << { name: "Página", value: feedback.source_url.truncate(256), inline: false }
      end

      ip = feedback.guest_metadata["ip"]
      fields << { name: "IP", value: ip.to_s.truncate(64), inline: true } if ip.present?

      fields
    end

    def self.precondition!(condition)
      raise ArgumentError, "precondition failed" unless condition
    end

    def self.postcondition!(condition)
      raise ArgumentError, "postcondition failed" unless condition
    end

    private_class_method :discord_payload, :discord_fields, :precondition!, :postcondition!
  end
end
