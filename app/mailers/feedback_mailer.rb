# frozen_string_literal: true

# [REQ-FIT-OPS-001] Notifies support inbox when users submit feedback.
class FeedbackMailer < ApplicationMailer
  default from: -> { ENV.fetch("MAILER_SENDER", "noreply@modusloop.com") }

  def admin_notify
    @feedback = params.fetch(:feedback)
    Feedback.precondition!(@feedback.is_a?(Feedback) && @feedback.persisted?)

    mail(
      to: ENV.fetch("FEEDBACK_NOTIFY_EMAIL", "soporte@modusloop.com"),
      subject: admin_notify_subject
    )
  end

  private

  def admin_notify_subject
    type_label = I18n.t("feedback.types.#{@feedback.feedback_type}", default: @feedback.feedback_type)
    "[moduSLoop] #{type_label}: #{@feedback.message.truncate(60)}"
  end
end
