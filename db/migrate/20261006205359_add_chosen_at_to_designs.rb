# Every click now draws several proposals, and the client keeps one of them.
# `chosen_at` records that choice: a design of a batch without it is still one
# of the proposals on offer.
#
# Batches made before this — the variants of a click — were never offered as a
# choice: they are marked chosen, so no lineage suddenly asks to pick again.
class AddChosenAtToDesigns < ActiveRecord::Migration[8.1]
  def up
    add_column :designs, :chosen_at, :datetime
    add_index :designs, :batch_token
    execute "UPDATE designs SET chosen_at = created_at WHERE batch_token IS NOT NULL"
  end

  def down
    remove_index :designs, :batch_token
    remove_column :designs, :chosen_at
  end
end
