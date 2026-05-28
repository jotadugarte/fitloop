class CreateCarts < ActiveRecord::Migration[8.1]
  def change
    create_table :carts do |t|
      t.string :kind, null: false

      t.references :nesting_run, null: true, foreign_key: true, index: false
      t.integer :tier_months, null: true

      t.string :currency_mode, null: false
      t.boolean :overage, null: false, default: false

      t.string :guest_token, null: true
      t.references :user, null: true, foreign_key: true, index: false

      t.integer :list_price_cents, null: false
      t.integer :sinpe_price_cents, null: false

      t.timestamps
    end

    add_index :carts, :guest_token,
              unique: true,
              where: "guest_token IS NOT NULL",
              name: "index_carts_on_guest_token_unique"
    add_index :carts, :user_id,
              unique: true,
              where: "user_id IS NOT NULL",
              name: "index_carts_on_user_id_unique"
    add_index :carts, :nesting_run_id,
              where: "nesting_run_id IS NOT NULL",
              name: "index_carts_on_nesting_run_id_present"
  end
end
