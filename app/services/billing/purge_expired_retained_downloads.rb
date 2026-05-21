# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-003] Purges retained_nested_dxf after retained_until (D56).
  class PurgeExpiredRetainedDownloads
    def self.call(at: Time.current)
      new(at: at).call
    end

    def initialize(at: Time.current)
      @at = at
    end

    def call
      DownloadGrant.single_purchase.where(retained_until: ...@at).find_each(&:purge_retained_blob!)
    end
  end
end
