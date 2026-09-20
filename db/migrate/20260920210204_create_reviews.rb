class CreateReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :reviews do |t|
      t.references :design, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: { to_table: :users }
      # Empty until someone takes it: in "first available" mode the review is
      # paid for before anybody is assigned.
      t.references :designer_profile, foreign_key: true
      t.references :review_level, null: false, foreign_key: true

      t.string :token, null: false
      t.string :status, null: false, default: "awaiting_payment"
      t.string :assignment_mode, null: false, default: "first_available"

      t.text :client_brief

      # --- Money, in cents, always -------------------------------------------
      # Copied from the level at purchase: a level whose price changes next
      # month must not rewrite what was paid.
      t.integer :price_cents, null: false, default: 0
      t.integer :platform_fee_cents, null: false, default: 0

      # --- Revisions ----------------------------------------------------------
      t.integer :revisions_included, null: false, default: 0
      t.integer :revisions_used, null: false, default: 0

      # --- Timeline -----------------------------------------------------------
      t.datetime :due_at
      t.datetime :paid_at
      t.datetime :delivered_at
      t.datetime :accepted_at
      t.datetime :canceled_at

      # --- Stripe -------------------------------------------------------------
      t.string :stripe_checkout_session_id
      t.string :stripe_payment_intent_id
      t.string :stripe_transfer_id
      t.integer :refunded_cents, null: false, default: 0

      # --- Designer returning the job ----------------------------------------
      t.string :return_reason_code
      t.text :return_message
      t.references :proposed_level, foreign_key: { to_table: :review_levels }
      t.integer :proposed_price_cents
      t.datetime :returned_at
      t.datetime :proposal_expires_at
      t.datetime :proposal_reminded_at

      # --- Reputation ----------------------------------------------------------
      t.integer :rating
      t.text :rating_comment

      t.timestamps
    end

    add_index :reviews, :token, unique: true
    add_index :reviews, :stripe_checkout_session_id, unique: true
    add_index :reviews, :stripe_payment_intent_id
    # The client's list and the designer's queue.
    add_index :reviews, [ :client_id, :created_at ]
    add_index :reviews, [ :designer_profile_id, :status ]
    # The sweeps read these together: what is due, what expires, what is owed.
    add_index :reviews, [ :status, :due_at ]
    add_index :reviews, [ :status, :proposal_expires_at ]
    add_index :reviews, [ :status, :delivered_at ]
  end
end
