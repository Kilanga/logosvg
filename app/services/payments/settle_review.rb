module Payments
  # Pays the designer, once, when the client accepts.
  #
  # Charges and transfers are separate on purpose: the money sits on the
  # platform's account until the client is satisfied, so a review that is
  # refunded never became the designer's in the first place.
  class SettleReview
    def self.call(...) = new(...).call

    def initialize(review:)
      @review = review
    end

    def call
      return :not_accepted unless @review.accepted?
      return :already_settled if @review.stripe_transfer_id.present?
      return :nothing_owed unless @review.designer_share_cents.positive?

      destination = @review.designer_profile&.stripe_account_id
      return :no_destination if destination.blank?
      return :not_configured unless StripeClient.configured?

      transfer(destination)
      ReviewMailer.paid(@review).deliver_later
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
      def transfer(destination)
        result = StripeClient.new.create_transfer(
          amount_cents: @review.designer_share_cents,
          destination: destination,
          source_transaction: nil,
          # Stable for this review: a retried webhook, or an administrator
          # pressing the button twice, must not pay twice.
          idempotency_key: "transfer-#{@review.token}"
        )

        @review.update!(stripe_transfer_id: result.id)
      end
  end
end
