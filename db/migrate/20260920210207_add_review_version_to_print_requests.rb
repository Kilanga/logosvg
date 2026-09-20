# A print request can carry the designer's corrected file rather than the one
# the generator produced. The column was in the data model from the start; the
# table it points at only exists now.
class AddReviewVersionToPrintRequests < ActiveRecord::Migration[8.1]
  def change
    add_reference :print_requests, :review_version, foreign_key: true, null: true
  end
end
