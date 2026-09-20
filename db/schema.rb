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

ActiveRecord::Schema[8.1].define(version: 2026_09_20_210210) do
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

  create_table "blocked_terms", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.integer "hits_count", default: 0, null: false
    t.datetime "last_hit_at"
    t.string "reason"
    t.string "term", null: false
    t.datetime "updated_at", null: false
    t.index ["active"], name: "index_blocked_terms_on_active"
    t.index ["created_by_id"], name: "index_blocked_terms_on_created_by_id"
    t.index ["term"], name: "index_blocked_terms_on_term", unique: true
  end

  create_table "designer_levels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "designer_profile_id", null: false
    t.bigint "review_level_id", null: false
    t.datetime "updated_at", null: false
    t.index ["designer_profile_id", "review_level_id"], name: "index_designer_levels_on_pair", unique: true
    t.index ["designer_profile_id"], name: "index_designer_levels_on_designer_profile_id"
    t.index ["review_level_id"], name: "index_designer_levels_on_review_level_id"
  end

  create_table "designer_profiles", force: :cascade do |t|
    t.boolean "accepting_work", default: true, null: false
    t.text "bio"
    t.string "city"
    t.datetime "created_at", null: false
    t.string "display_name", null: false
    t.string "languages", default: [], null: false, array: true
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.datetime "onboarding_started_at"
    t.boolean "payouts_enabled", default: false, null: false
    t.decimal "rating_avg", precision: 3, scale: 2
    t.integer "ratings_count", default: 0, null: false
    t.boolean "remote", default: true, null: false
    t.string "specialties", default: [], null: false, array: true
    t.string "status", default: "pending_review", null: false
    t.string "stripe_account_id"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["specialties"], name: "index_designer_profiles_on_specialties", using: :gin
    t.index ["status", "payouts_enabled", "accepting_work"], name: "index_designer_profiles_on_availability"
    t.index ["status"], name: "index_designer_profiles_on_status"
    t.index ["stripe_account_id"], name: "index_designer_profiles_on_stripe_account_id", unique: true
    t.index ["user_id"], name: "index_designer_profiles_on_user_id", unique: true
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
    t.bigint "review_version_id"
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
    t.index ["review_version_id"], name: "index_print_requests_on_review_version_id"
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

  create_table "review_levels", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.integer "price_cents"
    t.integer "revisions_included", default: 1, null: false
    t.integer "turnaround_hours", default: 48, null: false
    t.datetime "updated_at", null: false
    t.index ["active", "position"], name: "index_review_levels_on_active_and_position"
    t.index ["key"], name: "index_review_levels_on_key", unique: true
  end

  create_table "review_messages", force: :cascade do |t|
    t.bigint "author_id", null: false
    t.text "body", null: false
    t.datetime "created_at", null: false
    t.datetime "read_at"
    t.bigint "review_id", null: false
    t.datetime "updated_at", null: false
    t.index ["author_id"], name: "index_review_messages_on_author_id"
    t.index ["review_id", "created_at"], name: "index_review_messages_on_review_id_and_created_at"
    t.index ["review_id", "read_at"], name: "index_review_messages_on_review_id_and_read_at"
    t.index ["review_id"], name: "index_review_messages_on_review_id"
  end

  create_table "review_versions", force: :cascade do |t|
    t.jsonb "checks", default: {}, null: false
    t.datetime "created_at", null: false
    t.integer "inks_count"
    t.text "message"
    t.integer "number", null: false
    t.bigint "review_id", null: false
    t.datetime "updated_at", null: false
    t.index ["review_id", "number"], name: "index_review_versions_on_review_id_and_number", unique: true
    t.index ["review_id"], name: "index_review_versions_on_review_id"
  end

  create_table "reviews", force: :cascade do |t|
    t.datetime "accepted_at"
    t.text "admin_note"
    t.string "assignment_mode", default: "first_available", null: false
    t.datetime "canceled_at"
    t.text "client_brief"
    t.bigint "client_id", null: false
    t.datetime "created_at", null: false
    t.datetime "delivered_at"
    t.bigint "design_id", null: false
    t.bigint "designer_profile_id"
    t.datetime "designer_reminded_at"
    t.datetime "due_at"
    t.datetime "paid_at"
    t.integer "platform_fee_cents", default: 0, null: false
    t.integer "price_cents", default: 0, null: false
    t.datetime "proposal_expires_at"
    t.datetime "proposal_reminded_at"
    t.bigint "proposed_level_id"
    t.integer "proposed_price_cents"
    t.integer "rating"
    t.text "rating_comment"
    t.integer "refunded_cents", default: 0, null: false
    t.text "return_message"
    t.string "return_reason_code"
    t.datetime "returned_at"
    t.bigint "review_level_id", null: false
    t.integer "revisions_included", default: 0, null: false
    t.integer "revisions_used", default: 0, null: false
    t.datetime "settled_at"
    t.bigint "settled_by_id"
    t.string "status", default: "awaiting_payment", null: false
    t.string "stripe_checkout_session_id"
    t.string "stripe_payment_intent_id"
    t.string "stripe_transfer_id"
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["client_id", "created_at"], name: "index_reviews_on_client_id_and_created_at"
    t.index ["client_id"], name: "index_reviews_on_client_id"
    t.index ["design_id"], name: "index_reviews_on_design_id"
    t.index ["designer_profile_id", "status"], name: "index_reviews_on_designer_profile_id_and_status"
    t.index ["designer_profile_id"], name: "index_reviews_on_designer_profile_id"
    t.index ["proposed_level_id"], name: "index_reviews_on_proposed_level_id"
    t.index ["review_level_id"], name: "index_reviews_on_review_level_id"
    t.index ["settled_by_id"], name: "index_reviews_on_settled_by_id"
    t.index ["status", "delivered_at"], name: "index_reviews_on_status_and_delivered_at"
    t.index ["status", "due_at"], name: "index_reviews_on_status_and_due_at"
    t.index ["status", "proposal_expires_at"], name: "index_reviews_on_status_and_proposal_expires_at"
    t.index ["stripe_checkout_session_id"], name: "index_reviews_on_stripe_checkout_session_id", unique: true
    t.index ["stripe_payment_intent_id"], name: "index_reviews_on_stripe_payment_intent_id"
    t.index ["token"], name: "index_reviews_on_token", unique: true
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
  add_foreign_key "blocked_terms", "users", column: "created_by_id"
  add_foreign_key "designer_levels", "designer_profiles"
  add_foreign_key "designer_levels", "review_levels"
  add_foreign_key "designer_profiles", "users"
  add_foreign_key "designs", "designs", column: "parent_id"
  add_foreign_key "designs", "designs", column: "root_id"
  add_foreign_key "designs", "printers"
  add_foreign_key "designs", "users"
  add_foreign_key "generation_counters", "users"
  add_foreign_key "print_requests", "designs"
  add_foreign_key "print_requests", "printers"
  add_foreign_key "print_requests", "review_versions"
  add_foreign_key "print_requests", "users", column: "client_id"
  add_foreign_key "printer_techniques", "printers"
  add_foreign_key "printers", "users"
  add_foreign_key "review_messages", "reviews"
  add_foreign_key "review_messages", "users", column: "author_id"
  add_foreign_key "review_versions", "reviews"
  add_foreign_key "reviews", "designer_profiles"
  add_foreign_key "reviews", "designs"
  add_foreign_key "reviews", "review_levels"
  add_foreign_key "reviews", "review_levels", column: "proposed_level_id"
  add_foreign_key "reviews", "users", column: "client_id"
  add_foreign_key "reviews", "users", column: "settled_by_id"
  add_foreign_key "sessions", "users"
  add_foreign_key "subscriptions", "printers"
  add_foreign_key "workshop_link_visits", "printers"
end
