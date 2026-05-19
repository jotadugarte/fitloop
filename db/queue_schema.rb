# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_05_19_120000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "derived_pieces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "geometry_json", default: {}, null: false
    t.string "label", null: false
    t.string "parent_piece_key", null: false
    t.bigint "project_id", null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_derived_pieces_on_project_id"
  end

  create_table "nesting_runs", force: :cascade do |t|
    t.datetime "cancel_requested_at"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.jsonb "params_snapshot", default: {}, null: false
    t.bigint "project_id", null: false
    t.jsonb "report_json", default: {}, null: false
    t.datetime "started_at"
    t.string "status", default: "processing", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_nesting_runs_on_project_id"
  end

  create_table "orphan_resolutions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "last_nesting_run_id"
    t.string "piece_key", null: false
    t.bigint "project_id", null: false
    t.string "reason"
    t.string "resolution_state", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.index ["last_nesting_run_id"], name: "index_orphan_resolutions_on_last_nesting_run_id"
    t.index ["project_id", "piece_key"], name: "index_orphan_resolutions_on_project_id_and_piece_key", unique: true
    t.index ["project_id"], name: "index_orphan_resolutions_on_project_id"
  end

  create_table "project_layers", force: :cascade do |t|
    t.bigint "active_storage_attachment_id"
    t.string "color"
    t.datetime "created_at", null: false
    t.boolean "included", default: false, null: false
    t.string "layer_name", null: false
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["active_storage_attachment_id"], name: "index_project_layers_on_active_storage_attachment_id"
    t.index ["project_id", "active_storage_attachment_id", "layer_name"], name: "index_project_layers_on_project_attachment_and_name", unique: true
    t.index ["project_id"], name: "index_project_layers_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "curve_tolerance_mm", default: 0.1, null: false
    t.boolean "ephemeral", default: false, null: false
    t.datetime "estimated_finished_at"
    t.float "kerf_mm", default: 0.0, null: false
    t.float "margin_mm", default: 5.0, null: false
    t.integer "nesting_time_limit_sec", default: 600, null: false
    t.string "pin_digest"
    t.string "progress_message"
    t.integer "progress_percent"
    t.jsonb "session_workflow_log", default: [], null: false
    t.float "sheet_gap_mm", default: 15.0, null: false
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
  end

  create_table "sheet_stocks", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "height_mm", null: false
    t.bigint "project_id", null: false
    t.integer "quantity"
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.float "width_mm", null: false
    t.index ["project_id"], name: "index_sheet_stocks_on_project_id"
  end

  create_table "split_proposals", force: :cascade do |t|
    t.jsonb "child_piece_geometries", default: [], null: false
    t.datetime "created_at", null: false
    t.jsonb "cut_segments", default: [], null: false
    t.boolean "feasible", default: true, null: false
    t.jsonb "labels", default: [], null: false
    t.bigint "orphan_resolution_id", null: false
    t.string "plan_reason"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.integer "version", default: 1, null: false
    t.index ["orphan_resolution_id"], name: "index_split_proposals_on_orphan_resolution_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "derived_pieces", "projects"
  add_foreign_key "nesting_runs", "projects"
  add_foreign_key "orphan_resolutions", "nesting_runs", column: "last_nesting_run_id"
  add_foreign_key "orphan_resolutions", "projects"
  add_foreign_key "project_layers", "projects"
  add_foreign_key "sheet_stocks", "projects"
  add_foreign_key "split_proposals", "orphan_resolutions"
end
