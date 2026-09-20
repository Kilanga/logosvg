# Terms a prompt may not contain: brands, protected characters, whatever the
# administration has had to turn away.
#
# Checked on this side before the generator is called at all, so a refused
# prompt costs the client nothing and never reaches another machine. The
# service keeps its own list; this one is the platform's.
class CreateBlockedTerms < ActiveRecord::Migration[8.1]
  def change
    create_table :blocked_terms do |t|
      t.string :term, null: false
      t.string :reason
      t.boolean :active, null: false, default: true
      t.references :created_by, foreign_key: { to_table: :users }
      # Counted rather than logged: how often a term actually catches something
      # is what tells an administrator whether it earns its place.
      t.integer :hits_count, null: false, default: 0
      t.datetime :last_hit_at

      t.timestamps
    end

    # Stored folded, so the uniqueness is the real one rather than a
    # case-sensitive near-miss.
    add_index :blocked_terms, :term, unique: true
    add_index :blocked_terms, :active
  end
end
