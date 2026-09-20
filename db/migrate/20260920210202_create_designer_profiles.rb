class CreateDesignerProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :designer_profiles do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }

      t.string :display_name, null: false
      t.text :bio
      t.string :city
      t.decimal :latitude, precision: 10, scale: 6
      t.decimal :longitude, precision: 10, scale: 6
      # Works from anywhere: stays on the list whatever radius is asked for.
      t.boolean :remote, null: false, default: true

      t.string :specialties, array: true, null: false, default: []
      t.string :languages, array: true, null: false, default: []

      # The designer's own switch, distinct from the two below: away for a
      # fortnight is not the same as unvetted or unpaid.
      t.boolean :accepting_work, null: false, default: true
      t.string :status, null: false, default: "pending_review"

      # --- Stripe Connect ------------------------------------------------------
      # `payouts_enabled` is Stripe's word, copied in by webhook. Nothing is
      # ever assigned to a designer who cannot be paid.
      t.string :stripe_account_id
      t.boolean :payouts_enabled, null: false, default: false
      t.datetime :onboarding_started_at

      # --- Reputation ----------------------------------------------------------
      t.decimal :rating_avg, precision: 3, scale: 2
      t.integer :ratings_count, null: false, default: 0

      t.timestamps
    end

    add_index :designer_profiles, :status
    add_index :designer_profiles, :stripe_account_id, unique: true
    # The one question the assignment rule asks, on every review that is paid.
    add_index :designer_profiles, [ :status, :payouts_enabled, :accepting_work ],
              name: "index_designer_profiles_on_availability"
    add_index :designer_profiles, :specialties, using: :gin
  end
end
