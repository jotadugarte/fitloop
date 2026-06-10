# frozen_string_literal: true

module Notifications
  # [REQ-FIT-OPS-001] Async delivery of feedback notifications.
  class DeliverFeedbackJob < ApplicationJob
    queue_as :default

    def perform(feedback_id)
      feedback = Feedback.find(feedback_id)
      Notifications::Dispatcher.notify_feedback_submitted(feedback)
    end
  end
end
