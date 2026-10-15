# When a designer took the review on. From that moment a share of the price is
# theirs whatever happens next (decided on 15/10/2026): see
# Review#guaranteed_share_cents.
class AddClaimedAtToReviews < ActiveRecord::Migration[8.1]
  def up
    add_column :reviews, :claimed_at, :datetime

    # The reviews already past the claim: their delivery, or their last change,
    # is the best date there is. A review handed back before any delivery
    # cannot be told apart from one returned from the queue, and stays nil.
    execute <<~SQL.squish
      UPDATE reviews SET claimed_at = COALESCE(delivered_at, updated_at)
      WHERE status IN ('in_progress', 'delivered', 'disputed', 'accepted') AND designer_profile_id IS NOT NULL
    SQL
  end

  def down
    remove_column :reviews, :claimed_at
  end
end
