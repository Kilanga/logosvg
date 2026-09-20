# Which levels a designer accepts. A review is only ever offered to someone who
# signed up for that level.
class CreateDesignerLevels < ActiveRecord::Migration[8.1]
  def change
    create_table :designer_levels do |t|
      t.references :designer_profile, null: false, foreign_key: true
      t.references :review_level, null: false, foreign_key: true

      t.timestamps
    end

    # One row per pair: the form posts the whole set every time, and a repeat
    # must not become a second acceptance.
    add_index :designer_levels, [ :designer_profile_id, :review_level_id ],
              unique: true, name: "index_designer_levels_on_pair"
  end
end
