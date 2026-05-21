# frozen_string_literal: true

class AllowNullNestingRunOnDownloadGrants < ActiveRecord::Migration[8.0]
  def change
    change_column_null :download_grants, :nesting_run_id, true
  end
end
