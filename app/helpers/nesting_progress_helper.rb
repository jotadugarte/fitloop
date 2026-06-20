# frozen_string_literal: true

module NestingProgressHelper
  # [REQ-FIT-UI-005] Live locale for progress copy (DB may store a frozen translation).
  def nesting_progress_message(project)
    Nesting::LocalizedProgressMessage.for(project)
  end

  # [REQ-FIT-UI-003] Accessible progress bar label: phase message, percent, optional ETA copy.
  def nesting_progress_aria_valuetext(project, percent)
    parts = []
    message = nesting_progress_message(project)
    parts << message if message.present?
    parts << "#{percent}%" if percent.positive?
    if project.estimated_finished_at.present? && project.estimated_finished_at > Time.current
      remaining_sec = (project.estimated_finished_at - Time.current).to_i
      minutes = (remaining_sec / 60.0).ceil
      parts << I18n.t("nesting.time_remaining", minutes: minutes) if minutes > 0
    end
    parts.join(", ")
  end
end
