# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-003] Serves retained nested DXF from Mis pagos (D54).
  class RetainedDownload
    Expired = Class.new(StandardError)
    MissingBlob = Class.new(StandardError)

    def self.serve!(grant:, at: Time.current)
      new(grant: grant, at: at).serve!
    end

    def initialize(grant:, at: Time.current)
      @grant = grant
      @at = at
    end

    def serve!
      raise Expired unless @grant.retention_active?(@at)
      attachment = @grant.retained_nested_dxf
      raise MissingBlob unless attachment.attached?

      {
        data: attachment.download,
        filename: attachment.filename.to_s,
        content_type: attachment.content_type
      }
    end
  end
end
