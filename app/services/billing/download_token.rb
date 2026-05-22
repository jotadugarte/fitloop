# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-003] Time-limited signed download token (~15 min, D45).
  class DownloadToken
    InvalidToken = Class.new(StandardError)
    TTL = 15.minutes

    def self.issue(user:, nesting_run:)
      new.issue(user: user, nesting_run: nesting_run)
    end

    def self.verify(token)
      new.verify(token)
    end

    def issue(user:, nesting_run:)
      raise ArgumentError, "user and nesting_run must be persisted" unless user.persisted? && nesting_run.persisted?
      payload = {
        "user_id" => user.id,
        "nesting_run_id" => nesting_run.id,
        "exp" => TTL.from_now.to_i
      }
      verifier.generate(payload, purpose: :nested_dxf_download)
    end

    def verify(token)
      payload = verifier.verify(token, purpose: :nested_dxf_download)
      raise InvalidToken, "expired" if Time.current.to_i > payload.fetch("exp")

      payload.symbolize_keys
    rescue ActiveSupport::MessageVerifier::InvalidSignature
      raise InvalidToken, "invalid"
    end

    private

    def verifier
      Rails.application.message_verifier("billing/download")
    end
  end
end
