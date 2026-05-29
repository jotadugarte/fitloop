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

ActiveRecord::Schema[8.1].define(version: 2026_05_28_120000) do
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

  create_table "carts", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "currency_mode", null: false
    t.string "guest_token"
    t.string "kind", null: false
    t.integer "list_price_cents", null: false
    t.bigint "nesting_run_id"
    t.boolean "overage", default: false, null: false
    t.integer "sinpe_price_cents", null: false
    t.integer "tier_months"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["guest_token"], name: "index_carts_on_guest_token_unique", unique: true, where: "(guest_token IS NOT NULL)"
    t.index ["nesting_run_id"], name: "index_carts_on_nesting_run_id_present", where: "(nesting_run_id IS NOT NULL)"
    t.index ["user_id"], name: "index_carts_on_user_id_unique", unique: true, where: "(user_id IS NOT NULL)"
  end

  create_table "derived_pieces", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "decorations_json", default: [], null: false
    t.jsonb "geometry_json", default: {}, null: false
    t.string "label", null: false
    t.string "parent_piece_key", null: false
    t.bigint "project_id", null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_derived_pieces_on_project_id"
  end

  create_table "download_grants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.bigint "nesting_run_id"
    t.datetime "retained_until"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["nesting_run_id"], name: "index_download_grants_on_nesting_run_id"
    t.index ["user_id", "nesting_run_id"], name: "index_download_grants_on_user_id_and_nesting_run_id", unique: true
    t.index ["user_id"], name: "index_download_grants_on_user_id"
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

  create_table "payments", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, null: false
    t.datetime "created_at", null: false
    t.string "currency", null: false
    t.decimal "discount_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.string "failure_code"
    t.string "failure_message"
    t.string "gateway_provider"
    t.string "gateway_status"
    t.decimal "list_price", precision: 12, scale: 2, default: "0.0", null: false
    t.bigint "nesting_run_id"
    t.string "onvo_mode"
    t.string "onvo_payment_intent_id"
    t.datetime "paid_at"
    t.string "payment_method", null: false
    t.string "product_description", default: "", null: false
    t.string "purchaser_email", default: "", null: false
    t.string "purchaser_name", default: "", null: false
    t.string "purpose", null: false
    t.string "status", default: "pending", null: false
    t.bigint "subscription_id"
    t.decimal "subtotal", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "tax_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_amount", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["nesting_run_id"], name: "index_payments_on_nesting_run_id"
    t.index ["onvo_payment_intent_id"], name: "index_payments_on_onvo_payment_intent_id"
    t.index ["subscription_id"], name: "index_payments_on_subscription_id"
    t.index ["user_id"], name: "index_payments_on_user_id"
  end

  create_table "plan_monthly_usages", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "downloads_used", default: 0, null: false
    t.integer "period_month", null: false
    t.integer "period_year", null: false
    t.integer "quota_limit", default: 50, null: false
    t.bigint "subscription_id", null: false
    t.datetime "updated_at", null: false
    t.index ["subscription_id", "period_year", "period_month"], name: "index_plan_monthly_usages_on_subscription_period", unique: true
    t.index ["subscription_id"], name: "index_plan_monthly_usages_on_subscription_id"
  end

  create_table "project_layers", force: :cascade do |t|
    t.bigint "active_storage_attachment_id"
    t.string "color"
    t.datetime "created_at", null: false
    t.boolean "included", default: false, null: false
    t.string "layer_name", null: false
    t.string "layer_role"
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.index ["active_storage_attachment_id"], name: "index_project_layers_on_active_storage_attachment_id"
    t.index ["project_id", "active_storage_attachment_id", "layer_name"], name: "index_project_layers_on_project_attachment_and_name", unique: true
    t.index ["project_id", "active_storage_attachment_id"], name: "index_project_layers_one_primary_per_attachment", unique: true, where: "((layer_role)::text = 'primary'::text)"
    t.index ["project_id"], name: "index_project_layers_on_project_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.float "curve_tolerance_mm", default: 0.1, null: false
    t.boolean "ephemeral", default: true, null: false
    t.datetime "estimated_finished_at"
    t.float "kerf_mm", default: 0.0, null: false
    t.datetime "last_activity_at"
    t.float "margin_mm", default: 5.0, null: false
    t.integer "nesting_time_limit_sec", default: 600, null: false
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

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "index_solid_queue_blocked_executions_for_release"
    t.index ["expires_at", "concurrency_key"], name: "index_solid_queue_blocked_executions_for_maintenance"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_for_filtering"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_for_alerting"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_poll_all"
    t.index ["queue_name", "priority", "job_id"], name: "index_solid_queue_poll_by_queue"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "index_solid_queue_dispatch_all"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
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

  create_table "subscriptions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "ends_at", null: false
    t.datetime "starts_at", null: false
    t.integer "tier_months", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_subscriptions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "confirmation_sent_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name", default: "", null: false
    t.string "provider"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "suspended_at"
    t.datetime "terms_accepted_at"
    t.string "terms_version"
    t.string "time_zone"
    t.string "uid"
    t.string "unconfirmed_email"
    t.datetime "updated_at", null: false
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["provider", "uid"], name: "index_users_on_provider_and_uid", unique: true, where: "(provider IS NOT NULL)"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "carts", "nesting_runs"
  add_foreign_key "carts", "users"
  add_foreign_key "derived_pieces", "projects"
  add_foreign_key "download_grants", "nesting_runs"
  add_foreign_key "download_grants", "users"
  add_foreign_key "nesting_runs", "projects"
  add_foreign_key "orphan_resolutions", "nesting_runs", column: "last_nesting_run_id"
  add_foreign_key "orphan_resolutions", "projects"
  add_foreign_key "payments", "nesting_runs"
  add_foreign_key "payments", "subscriptions"
  add_foreign_key "payments", "users"
  add_foreign_key "plan_monthly_usages", "subscriptions"
  add_foreign_key "project_layers", "projects"
  add_foreign_key "sheet_stocks", "projects"
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "split_proposals", "orphan_resolutions"
  add_foreign_key "subscriptions", "users"
end
