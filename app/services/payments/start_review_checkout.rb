module Payments
  # Opens Checkout for a review, or for the difference when a client takes a
  # designer's proposal.
  #
  # The price is copied onto the review at this moment. A level whose price
  # changes next month must not rewrite what somebody already paid.
  class StartReviewCheckout
    Result = Data.define(:url, :error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(review:, amount_cents:, success_url:, cancel_url:, purpose: :review)
      @review = review
      @amount_cents = amount_cents
      @success_url = success_url
      @cancel_url = cancel_url
      @purpose = purpose
    end

    def call
      return failure(:not_configured) unless StripeClient.configured?
      return failure(:nothing_to_pay) unless @amount_cents.to_i.positive?

      session = open_session
      @review.update!(stripe_checkout_session_id: session.id)

      Result.new(url: session.url, error: nil)
    rescue StripeClient::NotConfigured
      failure(:not_configured)
    rescue StripeClient::Failed => e
      Rails.logger.error("[stripe] #{e.message}")
      failure(:unavailable)
    end

    private
      def failure(reason) = Result.new(url: nil, error: I18n.t("reviews.errors.#{reason}"))

      def open_session
        StripeClient.new.create_payment_session(
          amount_cents: @amount_cents,
          product_name: product_name,
          client_email: @review.client.email_address,
          client_reference_id: @review.token,
          # Read back by the webhook: the session alone does not say which of
          # our rows it belongs to, nor what it was for.
          metadata: { review_token: @review.token, purpose: @purpose.to_s },
          success_url: @success_url,
          cancel_url: @cancel_url,
          idempotency_key: "review-#{@review.token}-#{@purpose}-#{@amount_cents}"
        )
      end

      def product_name
        level = @purpose.to_s == "upgrade" ? @review.proposed_level : @review.review_level
        I18n.t("reviews.checkout.product", level: level&.name)
      end
  end
end
