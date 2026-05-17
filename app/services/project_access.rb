# frozen_string_literal: true

# [REQ-FIT-AUTH-001] Grants access to a project via user PIN or admin master PIN.
class ProjectAccess
  def self.granted?(project:, pin:)
    raise ArgumentError, "project is required" if project.blank?

    candidate = pin.to_s
    return false if candidate.blank?

    return true if project.authenticate_pin(candidate)
    return true if admin_pin_matches?(candidate)

    false
  end

  def self.admin_pin_matches?(pin)
    master = Rails.application.credentials.dig(:fitloop, :admin_pin)
    return false if master.blank?

    ActiveSupport::SecurityUtils.secure_compare(pin.to_s, master.to_s)
  end

  private_class_method :admin_pin_matches?
end
