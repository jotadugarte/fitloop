# frozen_string_literal: true

class AddNestingJobControls < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :estimated_finished_at, :datetime
    add_column :nesting_runs, :cancel_requested_at, :datetime
  end
end
