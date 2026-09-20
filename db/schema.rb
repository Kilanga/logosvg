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

ActiveRecord::Schema[8.1].define(version: 2026_09_20_210200) do
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

  create_table "designs", force: :cascade do |t|
    t.integer "colors_requested"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.text "error_message"
    t.string "generator_job_id"
    t.integer "inks_count"
    t.string "instruction"
    t.string "mode", default: "create", null: false
    t.jsonb "palette", default: [], null: false
    t.bigint "parent_id"
    t.integer "paths_count"
    t.string "print_format"
    t.integer "print_width_cm"
    t.bigint "printer_id"
    t.text "prompt", null: false
    t.text "prompt_used"
    t.integer "refinements_left"
    t.boolean "remove_background", default: true, null: false
    t.bigint "root_id"
    t.bigint "seed"
    t.jsonb "stats", default: {}, null: false
    t.string "status", default: "pending", null: false
    t.string "style", default: "illustration", null: false
    t.string "subject"
    t.string "technique", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.jsonb "warnings", default: [], null: false
    t.index ["deleted_at"], name: "index_designs_on_deleted_at"
    t.index ["generator_job_id"], name: "index_designs_on_generator_job_id"
    t.index ["parent_id"], name: "index_designs_on_parent_id"
    t.index ["printer_id"], name: "index_designs_on_printer_id"
    t.index ["root_id"], name: "index_designs_on_root_id"
    t.index ["status"], name: "index_designs_on_status"
    t.index ["technique"], name: "index_designs_on_technique"
    t.index ["token"], name: "index_designs_on_token", unique: true
    t.index ["user_id", "created_at"], name: "index_designs_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_designs_on_user_id"
  end

  create_table "generation_counters", force: :cascade do |t|
    t.integer "count", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "day", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "day"], name: "index_generation_counters_on_user_id_and_day", unique: true
    t.index ["user_id"], name: "index_generation_counters_on_user_id"
  end

  create_table "print_requests", force: :cascade do |t|
    t.datetime "acknowledged_at"
    t.bigint "client_id", null: false
    t.string "confirmation_token", null: false
    t.string "consent_text_version"
    t.datetime "consented_at"
    t.string "contact_city"
    t.string "contact_email"
    t.string "contact_name"
    t.string "contact_phone"
    t.datetime "created_at", null: false
    t.bigint "design_id", null: false
    t.date "desired_on"
    t.text "message"
    t.string "placements", default: [], null: false, array: true
    t.integer "print_width_cm"
    t.bigint "printer_id", null: false
    t.datetime "quoted_at"
    t.datetime "reminded_at"
    t.datetime "sent_at"
    t.jsonb "sizes", default: {}, null: false
    t.string "status", default: "sent", null: false
    t.string "textile_color"
    t.string "textile_model"
    t.string "textile_source", default: "printer", null: false
    t.string "token", null: false
    t.integer "total_qty", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["client_id", "created_at"], name: "index_print_requests_on_client_id_and_created_at"
    t.index ["client_id"], name: "index_print_requests_on_client_id"
    t.index ["confirmation_token"], name: "index_print_requests_on_confirmation_token", unique: true
    t.index ["design_id"], name: "index_print_requests_on_design_id"
    t.index ["printer_id", "status", "sent_at"], name: "index_print_requests_on_printer_id_and_status_and_sent_at"
    t.index ["printer_id"], name: "index_print_requests_on_printer_id"
    t.index ["status", "sent_at"], name: "index_print_requests_on_status_and_sent_at"
    t.index ["token"], name: "index_print_requests_on_token", unique: true
  end

  create_table "printer_techniques", force: :cascade do |t|
    t.string "color_space", default: "rgb", null: false
    t.datetime "created_at", null: false
    t.string "label"
    t.integer "max_colors"
    t.integer "max_print_height_cm"
    t.integer "max_print_width_cm"
    t.string "note"
    t.string "output_format", default: "svg", null: false
    t.boolean "primary", default: false, null: false
    t.bigint "printer_id", null: false
    t.string "technique", null: false
    t.datetime "updated_at", null: false
    t.index ["printer_id", "technique"], name: "index_printer_techniques_on_printer_id_and_technique", unique: true
    t.index ["printer_id"], name: "index_printer_techniques_on_printer_id"
    t.index ["printer_id"], name: "index_printer_techniques_on_single_primary", unique: true, where: "(\"primary\" = true)"
    t.index ["technique"], name: "index_printer_techniques_on_technique"
  end

  create_table "printers", force: :cascade do |t|
    t.boolean "accepts_client_textile", default: false, null: false
    t.string "address"
    t.string "brand_color"
    t.string "city"
    t.datetime "created_at", null: false
    t.text "description"
    t.boolean "express_available", default: false, null: false
    t.integer "express_lead_hours"
    t.boolean "featured", default: false, null: false
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.integer "max_print_height_cm"
    t.integer "max_print_width_cm"
    t.integer "min_order_qty"
    t.string "name", null: false
    t.jsonb "opening_hours", default: {}, null: false
    t.string "orders_email", null: false
    t.string "phone"
    t.boolean "pickup", default: false, null: false
    t.string "placements", default: [], null: false, array: true
    t.string "postal_code"
    t.text "price_note"
    t.boolean "provides_textile", default: false, null: false
    t.integer "response_time_hours"
    t.integer "shipping_lead", comment: "Shipping lead time, in days"
    t.string "shipping_price_note"
    t.string "shipping_zones", default: [], null: false, array: true
    t.boolean "ships", default: false, null: false
    t.string "slug", null: false
    t.integer "standard_lead_days"
    t.integer "status", default: 0, null: false
    t.string "textile_brands", default: [], null: false, array: true
    t.integer "textile_label", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.string "website"
    t.index ["city"], name: "index_printers_on_city"
    t.index ["featured"], name: "index_printers_on_featured"
    t.index ["latitude", "longitude"], name: "index_printers_on_latitude_and_longitude"
    t.index ["postal_code"], name: "index_printers_on_postal_code"
    t.index ["ships"], name: "index_printers_on_ships"
    t.index ["slug"], name: "index_printers_on_slug", unique: true
    t.index ["status"], name: "index_printers_on_status"
    t.index ["user_id"], name: "index_printers_on_user_id", unique: true
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "stripe_events", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error_message"
    t.string "event_type", null: false
    t.datetime "processed_at"
    t.string "stripe_id", null: false
    t.datetime "updated_at", null: false
    t.index ["event_type"], name: "index_stripe_events_on_event_type"
    t.index ["stripe_id"], name: "index_stripe_events_on_stripe_id", unique: true
  end

  create_table "subscriptions", force: :cascade do |t|
    t.datetime "canceled_at"
    t.datetime "created_at", null: false
    t.datetime "current_period_end"
    t.datetime "past_due_since"
    t.string "plan", default: "listing", null: false
    t.bigint "printer_id", null: false
    t.string "status", default: "incomplete", null: false
    t.string "stripe_customer_id"
    t.string "stripe_subscription_id"
    t.datetime "updated_at", null: false
    t.index ["printer_id"], name: "index_subscriptions_on_printer_id", unique: true
    t.index ["status", "past_due_since"], name: "index_subscriptions_on_status_and_past_due_since"
    t.index ["stripe_customer_id"], name: "index_subscriptions_on_stripe_customer_id"
    t.index ["stripe_subscription_id"], name: "index_subscriptions_on_stripe_subscription_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.string "city"
    t.datetime "created_at", null: false
    t.datetime "deleted_at"
    t.string "email_address", null: false
    t.string "first_name"
    t.string "last_name"
    t.string "password_digest", null: false
    t.string "phone"
    t.integer "role", default: 0, null: false
    t.datetime "terms_accepted_at"
    t.datetime "updated_at", null: false
    t.index ["deleted_at"], name: "index_users_on_deleted_at"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["role"], name: "index_users_on_role"
  end

  create_table "workshop_link_visits", force: :cascade do |t|
    t.integer "count", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "day", null: false
    t.bigint "printer_id", null: false
    t.datetime "updated_at", null: false
    t.index ["printer_id", "day"], name: "index_workshop_link_visits_on_printer_id_and_day", unique: true
    t.index ["printer_id"], name: "index_workshop_link_visits_on_printer_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "designs", "designs", column: "parent_id"
  add_foreign_key "designs", "designs", column: "root_id"
  add_foreign_key "designs", "printers"
  add_foreign_key "designs", "users"
  add_foreign_key "generation_counters", "users"
  add_foreign_key "print_requests", "designs"
  add_foreign_key "print_requests", "printers"
  add_foreign_key "print_requests", "users", column: "client_id"
  add_foreign_key "printer_techniques", "printers"
  add_foreign_key "printers", "users"
  add_foreign_key "sessions", "users"
  add_foreign_key "subscriptions", "printers"
  add_foreign_key "workshop_link_visits", "printers"
end
