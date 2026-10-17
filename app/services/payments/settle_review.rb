module Payments
  # Pays the designer, once, when the client accepts.
  #
  # Charges and transfers are separate on purpose: the money sits on the
  # platform's account until the client is satisfied, so a review that is
  # refunded never became the designer's in the first place.
  class SettleReview
    def self.call(...) = new(...).call

    # `notify` is false when another email already states the amount — an
    # administrator's decision, a closed proposal — and two messages about one
    # payment read as a mistake.
    def initialize(review:, notify: true)
      @review = review
      @notify = notify
    end

    def call
      return :not_accepted unless payable?
      return :already_settled if @review.stripe_transfer_id.present?
      return :nothing_owed unless @review.payout_cents.positive?

      destination = @review.designer_profile&.stripe_account_id
      return :no_destination if destination.blank?
      return :not_configured unless StripeClient.configured?

      transfer(destination)
      ReviewMailer.paid(@review).deliver_later if @notify
      :transferred
    rescue StripeClient::NotConfigured
      :not_configured
    rescue StripeClient::Failed => e
      # Left for an administrator rather than retried blindly: a transfer that
      # Stripe refuses usually needs a human to look at the account.
      Rails.logger.error("[stripe] transfer failed for review #{@review.token}: #{e.message}")
      :failed
    end

    private
      # Accepted, or closed after the designer took it on with their guaranteed
      # share recorded (decided on 15/10/2026).
      def payable?
        @review.accepted? || (@review.canceled? && @review.designer_payout_cents.to_i.positive?)
      end

      def transfer(destination)
        client = StripeClient.new
        result = client.create_transfer(
          amount_cents: @review.payout_cents,
          destination: destination,
          source_transaction: source_charge(client),
          # Stable for this review: a retried webhook, or an administrator
          # pressing the button twice, must not pay twice.
          idempotency_key: "transfer-#{@review.token}",
          description: I18n.t("payments.transfer_description", reference: @review.token,
                              level: ReviewLevel.where(id: @review.review_level_id).pick(:name)),
          metadata: { review: @review.token, design: Design.where(id: @review.design_id).pick(:token),
                      outcome: outcome }
        )

        @review.update!(stripe_transfer_id: result.id)
      end

      # How the review ended, for whoever reads the transfer in Stripe:
      # validated by the client (or by the week passing), shared by an
      # administrator after a refund, or closed with the designer's guaranteed
      # share (reported on 17/10/2026: a split read « accepted »).
      def outcome
        return "canceled" if @review.canceled?
        return "accepted" if @review.settled_at.blank?

        @review.refunded_cents.positive? ? "split" : "settled_by_admin"
      end

      # The client's charge, when the transfer fits inside it. Without it, a
      # client who accepts within the week the money takes to arrive would make
      # the transfer fail for want of an available balance. A review paid in
      # two goes (an upgrade) may owe more than the last charge brought: then
      # the platform's balance pays, as before.
      def source_charge(client)
        return nil if @review.stripe_payment_intent_id.blank?

        intent = client.retrieve_payment_intent(@review.stripe_payment_intent_id)
        charge = intent[:latest_charge]
        charge = charge[:id] if charge.is_a?(Hash)
        return nil if charge.blank?
        return nil if intent[:amount_received].to_i < @review.payout_cents

        charge
      rescue StripeClient::Failed => e
        Rails.logger.warn("[stripe] no source charge for review #{@review.token}: #{e.message}")
        nil
      end
  end
end
