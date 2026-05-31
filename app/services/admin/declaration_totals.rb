# frozen_string_literal: true

module Admin
  # [REQ-FIT-ADMIN-001] Succeeded-payment totals split by currency for Hacienda declarations.
  class DeclarationTotals
    Totals = Data.define(:count, :list_price, :discount_amount, :subtotal, :tax_amount, :total)

    def self.for_scope(scope)
      succeeded = scope.where(status: "succeeded")
      {
        crc: compute(succeeded.where(currency: "crc")),
        usd: compute(succeeded.where(currency: "usd"))
      }
    end

    def self.compute(relation)
      Totals.new(
        count: relation.count,
        list_price: relation.sum("COALESCE(list_price, 0)").to_f,
        discount_amount: relation.sum("COALESCE(discount_amount, 0)").to_f,
        subtotal: relation.sum("COALESCE(subtotal, 0)").to_f,
        tax_amount: relation.sum("COALESCE(tax_amount, 0)").to_f,
        total: relation.sum("COALESCE(NULLIF(total_amount, 0), amount)").to_f
      )
    end
  end
end
