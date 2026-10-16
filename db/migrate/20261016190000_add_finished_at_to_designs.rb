# When the generation service handed a design back, ready or failed: the wait a
# client went through, read by the admin dashboard to see whether the
# generation machine keeps up (decided on 16/10/2026).
class AddFinishedAtToDesigns < ActiveRecord::Migration[8.1]
  def change
    add_column :designs, :finished_at, :datetime
    add_index :designs, :created_at
  end
end
