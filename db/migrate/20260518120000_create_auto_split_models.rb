# frozen_string_literal: true

class CreateAutoSplitModels < ActiveRecord::Migration[8.1]
  def change
    change_table :projects, bulk: true do |t|
      t.jsonb :session_workflow_log, null: false, default: []
    end

    create_table :orphan_resolutions do |t|
      t.references :project, null: false, foreign_key: true
      t.string :piece_key, null: false
      t.string :resolution_state, null: false, default: "pending"
      t.string :reason
      t.references :last_nesting_run, foreign_key: { to_table: :nesting_runs }

      t.timestamps
    end

    add_index :orphan_resolutions, %i[project_id piece_key], unique: true

    create_table :split_proposals do |t|
      t.references :orphan_resolution, null: false, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.jsonb :cut_segments, null: false, default: []
      t.jsonb :child_piece_geometries, null: false, default: []
      t.jsonb :labels, null: false, default: []
      t.integer :version, null: false, default: 1

      t.timestamps
    end

    create_table :derived_pieces do |t|
      t.references :project, null: false, foreign_key: true
      t.string :parent_piece_key, null: false
      t.string :label, null: false
      t.jsonb :geometry_json, null: false, default: {}
      t.integer :sort_order, null: false, default: 0

      t.timestamps
    end
  end
end
