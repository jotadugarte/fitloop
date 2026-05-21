# frozen_string_literal: true

class CreateBillingTables < ActiveRecord::Migration[8.0]
  def change
    create_table :subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.integer :tier_months, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.timestamps
    end

    create_table :payments do |t|
      t.references :user, null: false, foreign_key: true
      t.references :nesting_run, foreign_key: true
      t.references :subscription, foreign_key: true
      t.string :status, null: false, default: "pending"
      t.string :payment_method, null: false
      t.string :currency, null: false
      t.decimal :amount, precision: 12, scale: 2, null: false
      t.string :purpose, null: false
      t.datetime :paid_at
      t.timestamps
    end

    create_table :download_grants do |t|
      t.references :user, null: false, foreign_key: true
      t.references :nesting_run, null: false, foreign_key: true
      t.string :kind, null: false
      t.datetime :retained_until
      t.timestamps
    end
    add_index :download_grants, %i[user_id nesting_run_id], unique: true

    create_table :plan_monthly_usages do |t|
      t.references :subscription, null: false, foreign_key: true
      t.integer :period_year, null: false
      t.integer :period_month, null: false
      t.integer :downloads_used, null: false, default: 0
      t.integer :quota_limit, null: false, default: 50
      t.timestamps
    end
    add_index :plan_monthly_usages, %i[subscription_id period_year period_month],
              unique: true, name: "index_plan_monthly_usages_on_subscription_period"
  end
end
