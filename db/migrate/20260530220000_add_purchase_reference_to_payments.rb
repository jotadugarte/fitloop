# frozen_string_literal: true

class AddPurchaseReferenceToPayments < ActiveRecord::Migration[8.1]
  def change
    change_table :payments, bulk: true do |t|
      t.string :purchase_reference, limit: 12
      t.index :purchase_reference,
              unique: true,
              where: "purchase_reference IS NOT NULL",
              name: "index_payments_on_purchase_reference_unique"
    end
  end
end
