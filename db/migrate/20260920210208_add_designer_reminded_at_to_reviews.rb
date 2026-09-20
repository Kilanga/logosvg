# Its own column rather than reusing `proposal_reminded_at`: the two mean
# different things — one chases a client about a proposal, the other tells a
# client their chosen designer has gone quiet — and a column that means two
# things is one nobody can query safely.
class AddDesignerRemindedAtToReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :reviews, :designer_reminded_at, :datetime
  end
end
