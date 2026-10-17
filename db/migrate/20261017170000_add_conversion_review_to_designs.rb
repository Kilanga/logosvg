# A designer's own conversion of a file to the workshop's format (asked for on
# 17/10/2026), offered only inside a client's review: the design it produces
# belongs to the designer and names the review it was made for.
class AddConversionReviewToDesigns < ActiveRecord::Migration[8.1]
  def change
    add_reference :designs, :conversion_review, foreign_key: { to_table: :reviews }, null: true, index: true
  end
end
