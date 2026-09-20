module Payments
  # Opens a Stripe Checkout session so a shop can subscribe.
  #
  # The row is created here, `incomplete`, before the shop ever reaches Stripe.
  # That is deliberate: the webhook that confirms the payment arrives with a
  # customer id and nothing else to hang it on, and a subscription that exists
  # beforehand is one the webhook can always find.
  class StartSubscription
    Result = Data.define(:url, :error) do
      def success? = error.nil?
    end

    def self.call(...) = new(...).call

    def initialize(printer:, plan:, success_url:, cancel_url:)
      @printer = printer
      @plan = plan.to_s
      @success_url = success_url
      @cancel_url = cancel_url
    end

    def call
      return failure(:unknown_plan) unless Subscription::PLANS.include?(@plan)
      return failure(:not_configured) unless StripeClient.configured?

      price = StripeClient.price_for(@plan)
      return failure(:not_configured) if price.blank?

      subscription = subscription_row
      session = open_session(price, subscription)

      Result.new(url: session.url, error: nil)
    rescue StripeClient::NotConfigured
      failure(:not_configured)
    rescue StripeClient::Failed => e
      Rails.logger.error("[stripe] #{e.message}")
      failure(:unavailable)
    end

    private
      def failure(reason) = Result.new(url: nil, error: I18n.t("subscriptions.errors.#{reason}"))

      # One row per shop, reused. A shop that abandons Checkout and comes back
      # must not end up with two.
      def subscription_row
        @printer.subscription || @printer.create_subscription!(plan: @plan, status: "incomplete")
      end

      def open_session(price, subscription)
        StripeClient.new.create_checkout_session(
          customer: subscription.stripe_customer_id,
          customer_email: @printer.orders_email,
          price: price,
          trial_days: Rails.application.config.tshirt.subscriptions[:trial_period_days],
          client_reference_id: @printer.id.to_s,
          success_url: @success_url,
          cancel_url: @cancel_url,
          # Stable for this shop and plan: clicking "subscribe" twice in a row
          # reaches the same Checkout session rather than opening a second one.
          idempotency_key: "checkout-#{@printer.id}-#{@plan}-#{subscription.updated_at.to_i}"
        )
      end
  end
end
