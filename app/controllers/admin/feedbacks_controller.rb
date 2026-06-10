# frozen_string_literal: true

module Admin
  # [REQ-FIT-OPS-001] Admin triage for user feedback submissions.
  class FeedbacksController < Admin::BaseController
    before_action :set_feedback, only: %i[update destroy]

    def index
      @status_filter = params[:status].to_s.presence
      @type_filter = params[:feedback_type].to_s.presence
      @feedbacks = Feedback.order(created_at: :desc)
      @feedbacks = @feedbacks.where(status: @status_filter) if @status_filter.present?
      @feedbacks = @feedbacks.where(feedback_type: @type_filter) if @type_filter.present?
    end

    def update
      status = Feedback::Status.parse(params.require(:status)).to_s
      if @feedback.update(status: status)
        redirect_to admin_feedbacks_path(redirect_filters), notice: t("feedback.admin.updated")
      else
        redirect_to admin_feedbacks_path(redirect_filters), alert: t("feedback.flash.error")
      end
    rescue ArgumentError
      redirect_to admin_feedbacks_path(redirect_filters), alert: t("feedback.flash.error")
    end

    def destroy
      @feedback.destroy!
      redirect_to admin_feedbacks_path(redirect_filters), notice: t("feedback.admin.destroyed")
    end

    private

    def set_feedback
      @feedback = Feedback.find(params[:id])
    end

    def redirect_filters
      request.query_parameters.slice("status", "feedback_type").compact_blank
    end
  end
end
