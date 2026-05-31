class AddCabysCodeToPayments < ActiveRecord::Migration[8.1]
  def change
    add_column :payments, :cabys_code, :string
  end
end
