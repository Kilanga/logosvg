module Reviews
  # The client says no to a designer's proposal, or lets it lapse — or calls
  # off a review whose chosen designer never answered.
  #
  # The review ends and the client is refunded — all of it when no designer
  # had started, all but the guaranteed share when one had (decided on
  # 15/10/2026, see Review#guaranteed_share_cents). That share is paid to the
  # designer who took it on, and the designer is told the review is closed
  # (reported on 15/10/2026: nobody told them).
  class DeclineProposal
    def self.call(...) = new(...).call

    def initialize(review:, notify_client: true)
      @review = review
      @notify_client = notify_client
    end

    def call
      # Worked out before the refund moves `refunded_cents`: a refund that
      # fails must not hand the designer what the client should have got back.
      payout = @review.guaranteed_payout_cents

      Payments::RefundReview.call(review: @review, amount_cents: @review.refundable_cents, notify: @notify_client)
      @review.reload
      @review.designer_payout_cents = payout if payout.positive?
      returned = @review.returned_to_client?
      # The chosen designer who never answered leaves nothing to decline: the
      # review is simply called off (it was refused here before 15/10/2026).
      returned ? @review.decline_proposal! : @review.cancel!
      @review.save!

      Payments::SettleReview.call(review: @review, notify: false) if payout.positive?
      ReviewMailer.proposal_declined(@review).deliver_later if returned && @review.designer_profile_id
      @review
    end
  end
end
