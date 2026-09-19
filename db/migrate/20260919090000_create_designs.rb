class CreateDesigns < ActiveRecord::Migration[8.1]
  def change
    create_table :designs do |t|
      t.references :user, null: false, foreign_key: true
      # The shop in context, from /a/:slug or the directory. Optional: a client
      # may create before choosing one.
      t.references :printer, foreign_key: true

      # Public URLs carry this, never the sequential id.
      t.string :token, null: false

      # --- Lineage -----------------------------------------------------------
      # A ready design is immutable: a variant or a refinement is a child.
      t.references :parent, foreign_key: { to_table: :designs }
      t.references :root, foreign_key: { to_table: :designs }
      t.string :mode, null: false, default: "create"
      t.string :instruction
      # Counted by the microservice over the lineage; Rails caches what it says
      # and never recomputes it.
      t.integer :refinements_left

      # --- What was asked ----------------------------------------------------
      t.text :prompt, null: false
      t.string :style, null: false, default: "illustration"
      # A catalogue key. Frozen once created: it shaped the prompt, not only the
      # output file.
      t.string :technique, null: false
      t.integer :colors_requested
      t.integer :print_width_cm
      t.boolean :remove_background, null: false, default: true
      t.bigint :seed

      # --- What came back ----------------------------------------------------
      t.string :status, null: false, default: "pending"
      t.string :generator_job_id
      t.text :error_message
      # svg or png: says which of the two the print file is.
      t.string :print_format
      t.integer :inks_count
      t.integer :paths_count
      t.jsonb :palette, null: false, default: []
      t.jsonb :warnings, null: false, default: []
      t.jsonb :stats, null: false, default: {}
      t.text :prompt_used
      t.string :subject

      t.datetime :deleted_at

      t.timestamps
    end

    add_index :designs, :token, unique: true
    add_index :designs, :status
    add_index :designs, :technique
    add_index :designs, :deleted_at
    add_index :designs, :generator_job_id
    # The client's own list, newest first.
    add_index :designs, [ :user_id, :created_at ]
  end
end
