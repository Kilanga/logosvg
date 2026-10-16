module Reviews
  # The client says yes to a level the designer proposed that costs the same
  # or less — a dearer one goes through Checkout first, then ApplyProposal.
  #
  # The difference comes back before the new level applies: the client must
  # never be on the cheaper level having paid for the dearer one (revue du
  # 16/10/2026: a refused refund applied the level all the same). Counted
  # apart from refunds against the price — see
  # Review#refunded_against_price_cents.
  class AcceptProposal
    Result = Data.define(:review, :error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(review:)
      @review = review
    end

    def call
      owed = -@review.proposal_difference_cents

      if owed.positive?
        refund = Payments::RefundReview.call(review: @review, amount_cents: owed)
        return Result.new(review: @review, error: I18n.t("reviews.errors.refund_failed")) if Payments::RefundReview.failed?(refund)

        if refund == :refunded
          @review.update!(price_change_refunded_cents: @review.price_change_refunded_cents + owed)
        end
      end

      ApplyProposal.call(review: @review)
      Result.new(review: @review, error: nil)
    end
  end
end
