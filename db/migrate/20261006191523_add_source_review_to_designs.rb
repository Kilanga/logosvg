# A design made from a designer's accepted delivery points back at the review
# it came from: once per review, and the screen can say who reworked it.
class AddSourceReviewToDesigns < ActiveRecord::Migration[8.1]
  def change
    add_reference :designs, :source_review, foreign_key: { to_table: :reviews }, index: { unique: true }
  end
end
