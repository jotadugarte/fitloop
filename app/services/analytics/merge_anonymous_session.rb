# frozen_string_literal: true

module Analytics
  class MergeAnonymousSession
    def self.call(anonymous_session_key, user_id)
      return if anonymous_session_key.blank? || user_id.blank?

      UserEvent.where(anonymous_session_key: anonymous_session_key, user_id: nil).update_all(user_id: user_id)
    end
  end
end
