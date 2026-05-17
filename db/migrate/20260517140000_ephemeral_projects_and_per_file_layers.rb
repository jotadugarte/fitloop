# frozen_string_literal: true

class EphemeralProjectsAndPerFileLayers < ActiveRecord::Migration[8.1]
  def change
    change_table :projects, bulk: true do |t|
      t.boolean :ephemeral, null: false, default: false
    end

    change_table :project_layers, bulk: true do |t|
      t.bigint :active_storage_attachment_id
    end

    remove_index :project_layers, name: "index_project_layers_on_project_id_and_layer_name"
    add_index :project_layers,
              %i[project_id active_storage_attachment_id layer_name],
              unique: true,
              name: "index_project_layers_on_project_attachment_and_name"
    add_index :project_layers, :active_storage_attachment_id
  end
end
