# What the designer hands back. Numbered continuously within a review, so the
# client can talk about "version 2" and mean one thing.
class CreateReviewVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :review_versions do |t|
      t.references :review, null: false, foreign_key: true
      t.integer :number, null: false
      t.text :message

      # What the inspection found: ink count for a vector file, dimensions and
      # effective resolution for a raster one. Kept so the workshop — and the
      # client — can see it without re-opening the file.
      t.jsonb :checks, null: false, default: {}
      t.integer :inks_count

      t.timestamps
    end

    # Numbered within a review, and only once per number.
    add_index :review_versions, [ :review_id, :number ], unique: true
  end
end
