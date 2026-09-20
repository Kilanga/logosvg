module Payments
  # Gives the client their money back, in whole or in part.
  #
  # Refunding what was already refunded is the failure this guards against:
  # `refunded_cents` is the running total, and nothing beyond the price ever
  # leaves.
  class RefundReview
    def self.call(...) = new(...).call

    # `notify` is false when the refund is part of a larger message the client
    # is about to receive anyway — an administrator's decision already states
    # the amount, and two emails about one event read as a mistake.
    def initialize(review:, amount_cents: nil, notify: true)
      @review = review
      @amount_cents = amount_cents
      @notify = notify
    end

    def call
      amount = capped_amount
      return :nothing_to_refund unless amount.positive?
      return :not_paid if @review.stripe_payment_intent_id.blank?
      return :not_configured unless StripeClient.configured?

      refund(amount)
      ReviewMailer.refunded(@review, amount).deliver_later if @notify
      :refunded
    rescue StripeClient::NotConfigured
      :not_configured
    rescue StripeClient::Failed => e
      Rails.logger.error("[stripe] refund failed for review #{@review.token}: #{e.message}")
      :failed
    end

    private
      # Never more than what is left to give back.
      def capped_amount
        asked = @amount_cents.presence || @review.price_cents
        remaining = @review.price_cents - @review.refunded_cents

        [ asked, remaining ].min.to_i.clamp(0, @review.price_cents)
      end

      def refund(amount)
        StripeClient.new.create_refund(
          payment_intent: @review.stripe_payment_intent_id,
          amount_cents: amount,
          idempotency_key: "refund-#{@review.token}-#{@review.refunded_cents}-#{amount}"
        )

        @review.update!(refunded_cents: @review.refunded_cents + amount)
      end
  end
end
