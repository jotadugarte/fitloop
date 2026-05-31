# frozen_string_literal: true

module Admin
  # [REQ-FIT-ADMIN-001] Payments included in ventas UI and XLSX (excludes superseded checkout attempts).
  module ReportingScope
    def self.call
      Payment.where(superseded_at: nil)
    end
  end
end
