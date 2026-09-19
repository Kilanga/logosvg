class CreatePrintRequests < ActiveRecord::Migration[8.1]
  def change
    create_table :print_requests do |t|
      t.references :design, null: false, foreign_key: true
      # Denormalised from the design on purpose: the client of a request never
      # changes, even if the design is later deleted.
      t.references :client, null: false, foreign_key: { to_table: :users }
      t.references :printer, null: false, foreign_key: true

      # Public URLs carry this; the workshop's confirmation link carries the
      # other. Two tokens because they are handed to different people — the
      # confirmation one travels by email and dies with a cancellation.
      t.string :token, null: false
      t.string :confirmation_token, null: false

      t.string :status, null: false, default: "sent"

      # --- The job ------------------------------------------------------------
      t.string :textile_source, null: false, default: "printer"
      t.string :textile_model
      t.string :textile_color
      t.string :placements, array: true, null: false, default: []
      # Copied from the design at send time: the design may father variants, and
      # what was ordered must not move afterwards.
      t.integer :print_width_cm
      # Size to quantity, e.g. {"M" => 10, "L" => 5}.
      t.jsonb :sizes, null: false, default: {}
      t.integer :total_qty, null: false, default: 0
      t.date :desired_on
      t.text :message

      # --- Who to answer ------------------------------------------------------
      t.string :contact_name
      t.string :contact_email
      t.string :contact_phone
      t.string :contact_city

      # --- Consent, kept as given --------------------------------------------
      t.string :consent_text_version
      t.datetime :consented_at

      # --- Timeline -----------------------------------------------------------
      t.datetime :sent_at
      t.datetime :acknowledged_at
      t.datetime :quoted_at
      t.datetime :reminded_at

      t.timestamps
    end

    add_index :print_requests, :token, unique: true
    add_index :print_requests, :confirmation_token, unique: true
    # The workshop's list, filtered by status and newest first.
    add_index :print_requests, [ :printer_id, :status, :sent_at ]
    # The client's list.
    add_index :print_requests, [ :client_id, :created_at ]
    # The reminder and expiry sweeps read these two together.
    add_index :print_requests, [ :status, :sent_at ]
  end
end
