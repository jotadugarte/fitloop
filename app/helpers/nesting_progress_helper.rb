# frozen_string_literal: true

module NestingProgressHelper
  # [REQ-FIT-UI-003] Accessible progress bar label: phase message, percent, optional ETA copy.
  def nesting_progress_aria_valuetext(project, percent)
    parts = []
    parts << project.progress_message if project.progress_message.present?
    parts << "#{percent}%" if percent.positive?
    parts.join(", ")
  end
end
