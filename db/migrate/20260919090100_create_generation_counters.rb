# One row per client per day. A counter rather than a count of designs: a
# failed generation must not consume quota, and deleting a design must not give
# an attempt back.
class CreateGenerationCounters < ActiveRecord::Migration[8.1]
  def change
    create_table :generation_counters do |t|
      t.references :user, null: false, foreign_key: true
      t.date :day, null: false
      t.integer :count, null: false, default: 0

      t.timestamps
    end

    # Unique so the counter can be incremented by an upsert, which is what makes
    # two simultaneous submissions impossible to slip past the quota.
    add_index :generation_counters, [ :user_id, :day ], unique: true
  end
end
