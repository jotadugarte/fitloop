class AddColorToProjectLayers < ActiveRecord::Migration[8.1]
  def change
    add_column :project_layers, :color, :string
  end
end
