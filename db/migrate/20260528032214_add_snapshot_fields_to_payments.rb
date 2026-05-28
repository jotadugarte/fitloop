class AddSnapshotFieldsToPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :payments, :purchaser_name, :string, null: false, default: ""
    add_column :payments, :purchaser_email, :string, null: false, default: ""
    add_column :payments, :product_description, :string, null: false, default: ""

    add_column :payments, :list_price, :decimal, precision: 12, scale: 2, null: false, default: 0
    add_column :payments, :discount_amount, :decimal, precision: 12, scale: 2, null: false, default: 0
    add_column :payments, :subtotal, :decimal, precision: 12, scale: 2, null: false, default: 0
    add_column :payments, :tax_amount, :decimal, precision: 12, scale: 2, null: false, default: 0
    add_column :payments, :total_amount, :decimal, precision: 12, scale: 2, null: false, default: 0
  end
end
