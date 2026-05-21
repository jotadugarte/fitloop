# frozen_string_literal: true

class AddLayerRoleToProjectLayers < ActiveRecord::Migration[8.1]
  def change
    add_column :project_layers, :layer_role, :string

    add_index :project_layers,
              %i[project_id active_storage_attachment_id],
              unique: true,
              where: "layer_role = 'primary'",
              name: "index_project_layers_one_primary_per_attachment"
  end
end
