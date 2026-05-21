# frozen_string_literal: true

module Accounts
  # [REQ-FIT-AUTH-002] Opt-in link of OAuth identity onto an existing email account.
  class Merge
    def self.apply!(user:, pending_oauth:, password:)
      new(user: user, pending_oauth: pending_oauth, password: password).apply!
    end

    def initialize(user:, pending_oauth:, password:)
      @user = user
      @pending_oauth = pending_oauth
      @password = password
    end

    def apply!
      precondition!(@user.present? && @pending_oauth.present?)
      raise MergeRejected, "invalid password" unless @user.valid_password?(@password)

      @user.update!(
        provider: @pending_oauth["provider"],
        uid: @pending_oauth["uid"],
        name: @pending_oauth["name"].presence || @user.name,
        time_zone: @pending_oauth["time_zone"].presence || @user.time_zone,
        confirmed_at: @user.confirmed_at || Time.current
      )
      @user
    end

    private

    def precondition!(condition)
      raise ArgumentError, "precondition failed" unless condition
    end
  end

  class MergeRejected < StandardError; end
end
