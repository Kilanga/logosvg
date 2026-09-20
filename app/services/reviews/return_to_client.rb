module Reviews
  # A designer hands the job back, because the option the client bought does
  # not let them do it properly.
  #
  # Two of the five reasons carry a proposal — a different level, or a price
  # for a custom job — and the review waits for the client's answer. The other
  # three end it there and then: the design is unusable or forbidden, and no
  # level would change that, so the client is refunded at once.
  #
  # See docs/SPEC.md, "Renvoi au client par le graphiste".
  class ReturnToClient
    Result = Data.define(:review, :error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(review:, reason:, message:, proposed_level: nil, proposed_price_cents: nil)
      @review = review
      @reason = reason.to_s
      @message = message.to_s.strip
      @proposed_level = proposed_level
      @proposed_price_cents = proposed_price_cents
    end

    def call
      return failure(:unknown_reason) unless Review::RETURN_REASONS.include?(@reason)
      return failure(:message_required) if @message.blank?
      return failure(:already_returned) unless @review.returnable?
      return failure(:proposal_required) if proposing? && proposed_amount.nil?

      @review.assign_attributes(
        return_reason_code: @reason,
        return_message: @message,
        proposed_level: (@proposed_level if proposing?),
        proposed_price_cents: (@proposed_price_cents if proposing?),
        proposal_expires_at: (expiry if proposing?)
      )

      @review.return_to_client!
      @review.save!

      # No proposal to answer means nothing to wait for: refund now.
      refund_outright unless proposing?

      ReviewMailer.returned_to_client(@review).deliver_later
      Result.new(review: @review, error: nil)
    end

    private
      def failure(reason) = Result.new(review: @review, error: I18n.t("reviews.errors.#{reason}"))

      def proposing? = Review::PROPOSING_REASONS.include?(@reason)

      def proposed_amount
        @proposed_price_cents.presence || @proposed_level&.price_cents
      end

      def expiry
        Rails.application.config.tshirt.reviews[:proposal_expiry_hours].hours.from_now
      end

      # The designer did the reading, not the work, and that is not billed.
      def refund_outright
        Payments::RefundReview.call(review: @review, amount_cents: @review.price_cents)
        @review.decline_proposal!
        @review.save!
      end
  end
end
