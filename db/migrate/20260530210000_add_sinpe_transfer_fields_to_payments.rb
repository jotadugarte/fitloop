# frozen_string_literal: true

class AddSinpeTransferFieldsToPayments < ActiveRecord::Migration[8.1]
  def change
    change_table :payments, bulk: true do |t|
      t.string :sinpe_transfer_identification
      t.string :sinpe_transfer_mobile_number
    end
  end
end
