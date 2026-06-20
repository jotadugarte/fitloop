class AddGapsToProjectLayers < ActiveRecord::Migration[8.1]
  def change
    add_column :project_layers, :auto_close_gaps, :boolean, default: false, null: false
    add_column :project_layers, :gaps_detected, :jsonb, default: [], null: false
  end
end
