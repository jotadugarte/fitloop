# frozen_string_literal: true

module Admin
  # [REQ-FIT-ADMIN-001] Paginated payment listing for admin ventas tables.
  class VentasListing
    Listing = Data.define(:payments, :page, :total_count, :total_pages)

    PER_PAGE = 20

    def self.call(scope, direction:, page:)
      page = [ page.to_i, 1 ].max
      total_count = scope.count
      total_pages = [ (total_count.to_f / PER_PAGE).ceil, 1 ].max
      payments = scope
        .includes(:user)
        .order(created_at: direction.to_sym)
        .limit(PER_PAGE)
        .offset((page - 1) * PER_PAGE)

      Listing.new(payments: payments, page: page, total_count: total_count, total_pages: total_pages)
    end
  end
end
