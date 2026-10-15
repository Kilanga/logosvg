# The part of `refunded_cents` that came back because the price itself went
# down — a cheaper level, or a custom job quoted outside — rather than as a
# refund against the price. Without it, a review moved to a cheaper level
# counted that difference twice: once in the lower price, once as a refund.
class AddPriceChangeRefundedCentsToReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :reviews, :price_change_refunded_cents, :integer, null: false, default: 0
    add_check_constraint :reviews, "price_change_refunded_cents >= 0", name: "reviews_price_change_refunded_positive"
  end
end
