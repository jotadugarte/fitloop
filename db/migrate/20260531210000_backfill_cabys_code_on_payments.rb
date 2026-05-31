# frozen_string_literal: true

class BackfillCabysCodeOnPayments < ActiveRecord::Migration[8.1]
  def up
    code = Payment::DEFAULT_CABYS_CODE
    execute <<-SQL.squish
      UPDATE payments
      SET cabys_code = #{connection.quote(code)}
      WHERE cabys_code IS NULL OR cabys_code = ''
    SQL
  end

  def down
    # no-op: cannot safely distinguish pre-backfill NULLs
  end
end
