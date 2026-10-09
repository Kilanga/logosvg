# When a review last went into the queue: paid, opened without payment, or
# put back after a proposal or a change of designer. A review nobody takes is
# refunded `reviews.unclaimed_refund_hours` after it (decided on 09/10/2026).
class AddQueuedAtToReviews < ActiveRecord::Migration[8.1]
  def up
    add_column :reviews, :queued_at, :datetime
    execute "UPDATE reviews SET queued_at = COALESCE(paid_at, created_at) WHERE status = 'queued'"
  end

  def down
    remove_column :reviews, :queued_at
  end
end
