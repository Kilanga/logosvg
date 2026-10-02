class AddDesignerReassignmentToReviews < ActiveRecord::Migration[8.1]
  def change
    # How many designers in a row have handed this review back at a proposed
    # level — the cap on how many times the client may pick a new one.
    add_column :reviews, :designer_refusals_count, :integer, null: false, default: 0
    # Excluded from the client's next pick: trying the same designer again
    # would not be a different answer.
    add_column :reviews, :refused_designer_profile_ids, :bigint, array: true, null: false, default: []
  end
end
