# frozen_string_literal: true

class Workspace
  # TTL and activity timestamps for ephemeral projects (D20).
  module Activity
    ACTIVITY_TTL = 120.seconds

    def activity_expired?(project)
      return false if project.last_activity_at.nil?

      project.last_activity_at < ACTIVITY_TTL.ago
    end

    def touch_activity!(project)
      project.update!(last_activity_at: Time.current)
    end
  end
end
