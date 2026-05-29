# frozen_string_literal: true

class AddOnvoGatewayFieldsToPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :payments, :gateway_provider, :string
    add_column :payments, :onvo_payment_intent_id, :string
    add_column :payments, :onvo_mode, :string
    add_column :payments, :gateway_status, :string
    add_column :payments, :failure_code, :string
    add_column :payments, :failure_message, :string

    add_index :payments, :onvo_payment_intent_id
  end
end
