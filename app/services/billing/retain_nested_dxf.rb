# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-003] Copies nested_dxf to grant before workspace discard (D54).
  class RetainNestedDxf
    RETENTION_HOURS = 24

    def self.call(grant:, nesting_run:, paid_at: Time.current)
      new(grant: grant, nesting_run: nesting_run, paid_at: paid_at).call
    end

    def initialize(grant:, nesting_run:, paid_at: Time.current)
      @grant = grant
      @nesting_run = nesting_run
      @paid_at = paid_at
    end

    def call
      source = @nesting_run.project.nested_dxf
      raise ArgumentError, "nested_dxf missing" unless source.attached?

      @grant.retained_nested_dxf.attach(
        io: StringIO.new(source.download),
        filename: source.filename.to_s,
        content_type: source.content_type
      )
      @grant.update!(retained_until: @paid_at + RETENTION_HOURS.hours) if @grant.retained_until.blank?
      @grant
    end
  end
end
