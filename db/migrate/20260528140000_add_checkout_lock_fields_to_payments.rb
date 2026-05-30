# frozen_string_literal: true

class AddCheckoutLockFieldsToPayments < ActiveRecord::Migration[8.1]
  def change
    change_table :payments, bulk: true do |t|
      t.datetime :checkout_lock_released_at
      t.datetime :checkout_abandoned_at
      t.datetime :superseded_at
      t.string :checkout_lock_reason
    end
  end
end
