# What a client can buy from a designer, and what the designer signs up to
# deliver. Administered from /admin at step 9; seeded so the rest can exist.
class CreateReviewLevels < ActiveRecord::Migration[8.1]
  def change
    create_table :review_levels do |t|
      t.string :key, null: false
      t.string :name, null: false
      t.text :description

      # Nil means "sur devis": the designer quotes it. Cents, never a float —
      # see docs/SPEC.md, "Montants en centimes".
      t.integer :price_cents

      t.integer :turnaround_hours, null: false, default: 48
      t.integer :revisions_included, null: false, default: 1
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :review_levels, :key, unique: true
    # The order the client reads them in.
    add_index :review_levels, [ :active, :position ]
  end
end
