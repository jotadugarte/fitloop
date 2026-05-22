# frozen_string_literal: true

module Billing
  # [REQ-FIT-BILL-003] Scheduled purge of expired retained nested DXF blobs (D56).
  class PurgeExpiredRetainedDownloadsJob < ApplicationJob
    queue_as :default

    def perform
      PurgeExpiredRetainedDownloads.call
    end
  end
end
