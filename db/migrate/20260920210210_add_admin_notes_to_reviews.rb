# What an administrator decided, and why. A dispute settled without a record
# of the reasoning is one nobody can answer questions about six months later.
class AddAdminNotesToReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :reviews, :admin_note, :text
    add_reference :reviews, :settled_by, foreign_key: { to_table: :users }
    add_column :reviews, :settled_at, :datetime
  end
end
