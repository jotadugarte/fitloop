# frozen_string_literal: true

module Accounts
  # [REQ-FIT-AUTH-002] Detects when OAuth email matches an account with a different sign-in method.
  class OauthCollision
    SESSION_KEY = :pending_oauth_merge
    USER_ID_KEY = :pending_merge_user_id

    def self.merge_required?(existing_user, auth)
      precondition!(existing_user.present? && auth.present?)
      return false if existing_user.provider.to_s == auth.provider.to_s && existing_user.uid.to_s == auth.uid.to_s

      existing_user.email.to_s.downcase == auth.info.email.to_s.strip.downcase
    end

    def self.stash!(session, existing_user:, auth:, time_zone:)
      precondition!(merge_required?(existing_user, auth))
      session[SESSION_KEY] = {
        "provider" => auth.provider.to_s,
        "uid" => auth.uid.to_s,
        "email" => auth.info.email.to_s,
        "name" => auth.info.name.to_s,
        "time_zone" => time_zone
      }
      session[USER_ID_KEY] = existing_user.id
    end

    def self.clear!(session)
      session.delete(SESSION_KEY)
      session.delete(USER_ID_KEY)
    end

    def self.pending(session)
      data = session[SESSION_KEY]
      user_id = session[USER_ID_KEY]
      return nil unless data && user_id

      user = User.find_by(id: user_id)
      return nil unless user

      { user: user, oauth: data }
    end

    def self.precondition!(condition)
      raise ArgumentError, "precondition failed" unless condition
    end
    private_class_method :precondition!
  end
end
