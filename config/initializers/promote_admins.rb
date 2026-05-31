# frozen_string_literal: true

# [REQ-FIT-ADMIN-001] Promote users listed in FITLOOP_ADMIN_EMAILS to admin on boot.
# Emails are comma-separated. Set in .env (dev) or server ENV (production).
# Real admin emails must NEVER be committed to source control.
# Example: FITLOOP_ADMIN_EMAILS=you@example.com,partner@example.com
Rails.application.config.after_initialize do
  # Skip admin promotion if users table doesn't exist yet (e.g. during db:migrate / db:setup)
  if ActiveRecord::Base.connection.table_exists?("users")
    emails = ENV
      .fetch("FITLOOP_ADMIN_EMAILS", "")
      .split(",")
      .map(&:strip)
      .reject(&:blank?)

    if emails.any?
      promoted = User.where(email: emails, admin: false).update_all(admin: true)
      Rails.logger.info "[AdminSeed] Promoted #{promoted} user(s) to admin." if promoted > 0
    end
  end
rescue => e
  Rails.logger.warn "[AdminSeed] Skipped admin promotion: #{e.message}"
end
