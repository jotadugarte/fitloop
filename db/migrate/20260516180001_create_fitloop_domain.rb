# frozen_string_literal: true

class CreateFitloopDomain < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :title, null: false
      t.string :pin_digest
      t.float :kerf_mm, null: false, default: 0.0
      t.float :margin_mm, null: false, default: 5.0
      t.float :curve_tolerance_mm, null: false, default: 0.1
      t.float :sheet_gap_mm, null: false, default: 15.0
      t.integer :nesting_time_limit_sec, null: false, default: 600
      t.string :status, null: false, default: "draft"
      t.integer :progress_percent
      t.string :progress_message

      t.timestamps
    end

    create_table :sheet_stocks do |t|
      t.references :project, null: false, foreign_key: true
      t.float :width_mm, null: false
      t.float :height_mm, null: false
      t.integer :quantity
      t.integer :sort_order, null: false, default: 0

      t.timestamps
    end

    create_table :project_layers do |t|
      t.references :project, null: false, foreign_key: true
      t.string :layer_name, null: false
      t.boolean :included, null: false, default: false

      t.timestamps
    end

    add_index :project_layers, %i[project_id layer_name], unique: true

    create_table :nesting_runs do |t|
      t.references :project, null: false, foreign_key: true
      t.string :status, null: false, default: "processing"
      t.jsonb :params_snapshot, null: false, default: {}
      t.jsonb :report_json, null: false, default: {}
      t.datetime :started_at
      t.datetime :finished_at

      t.timestamps
    end
  end
end
