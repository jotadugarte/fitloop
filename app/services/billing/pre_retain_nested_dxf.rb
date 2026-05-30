# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-001] [REQ-FIT-BILL-003] Stage nested DXF on grant before SINPE payment confirms (no retained_until).
  class PreRetainNestedDxf
    def self.call(user:, nesting_run:)
      new(user: user, nesting_run: nesting_run).call
    end

    def initialize(user:, nesting_run:)
      @user = user
      @nesting_run = nesting_run
    end

    def call
      raise ArgumentError, "user required" if @user.nil?
      raise ArgumentError, "nesting_run required" if @nesting_run.nil?

      grant = find_or_initialize_grant
      attach_blob!(grant)
      grant.save!
      grant
    end

    private

    def find_or_initialize_grant
      grant = DownloadGrant.find_or_initialize_by(user_id: @user.id, nesting_run_id: @nesting_run.id)
      grant.kind = "single_purchase"
      grant.retained_until = nil unless grant.retention_committed?
      grant
    end

    def attach_blob!(grant)
      source = @nesting_run.project.nested_dxf
      raise ArgumentError, "nested_dxf missing" unless source.attached?

      grant.purge_retained_blob! if grant.retained_nested_dxf.attached?
      grant.retained_nested_dxf.attach(
        io: StringIO.new(source.download),
        filename: source.filename.to_s,
        content_type: source.content_type
      )
    end
  end
end
