# frozen_string_literal: true

# [REQ-FIT-OPS-001] Accepts user feedback submissions from the workshop FAB dialog.
class FeedbacksController < ApplicationController
  def create
    @feedback = build_feedback

    if @feedback.save
      Notifications::DeliverFeedbackJob.perform_later(@feedback.id)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_back fallback_location: root_path, notice: t("feedback.flash.success") }
      end
    else
      respond_to do |format|
        format.turbo_stream { render status: :unprocessable_content }
        format.html do
          redirect_back fallback_location: root_path, alert: t("feedback.flash.error")
        end
      end
    end
  end

  private

  def build_feedback
    guest_context = if user_signed_in?
      nil
    else
      Feedback::GuestContext.from_request(
        request: request,
        source_url: feedback_params[:source_url]
      )
    end

    Feedback.build_from_params(
      params: feedback_params,
      user: user_signed_in? ? current_user : nil,
      guest_context: guest_context
    )
  end

  def feedback_params
    params.require(:feedback).permit(:feedback_type, :email, :message, :source_url)
  end
end
