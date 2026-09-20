module Reviews
  # Puts a review back in the queue at the level the designer proposed.
  #
  # Called once the money has moved — after Checkout for an upgrade, or right
  # away for a downgrade, where the difference comes back to the client instead.
  # The level and the price are rewritten together: a review whose level says
  # one thing and whose price says another is one nobody can settle.
  class ApplyProposal
    def self.call(...) = new(...).call

    def initialize(review:)
      @review = review
    end

    def call
      return :not_returned unless @review.returned_to_client?

      level = @review.proposed_level
      amount = @review.proposed_amount_cents
      return :no_proposal if amount.nil?

      @review.assign_attributes(
        review_level: level || @review.review_level,
        price_cents: amount,
        platform_fee_cents: fee_for(level, amount),
        revisions_included: level&.revisions_included || @review.revisions_included,
        # Back to a clean slate: the new level brings its own allowance.
        revisions_used: 0,
        due_at: nil
      )

      @review.accept_proposal!
      @review.save!

      ReviewMailer.notify_designers(@review).deliver_later
      :queued
    end

    private
      def fee_for(level, amount)
        (level || @review.review_level).platform_fee_cents(amount)
      end
  end
end
