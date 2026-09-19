module Payments
  # Copies a Stripe subscription onto our row.
  #
  # Stripe is the authority on status and dates; Rails never decides them and
  # never guesses. What this object owns is the consequences: when a listing
  # goes dark, when a shop is highlighted, and when the moment a payment failed
  # was — which is what the grace period counts from.
  class SyncSubscription
    def self.call(...) = new(...).call

    def initialize(subscription:, stripe_subscription:)
      @subscription = subscription
      @stripe = stripe_subscription
    end

    def call
      previous_status = @subscription.status

      @subscription.assign_attributes(
        status: status,
        plan: plan_from_price || @subscription.plan,
        stripe_subscription_id: @stripe[:id],
        stripe_customer_id: @stripe[:customer] || @subscription.stripe_customer_id,
        current_period_end: timestamp(@stripe[:current_period_end]),
        canceled_at: timestamp(@stripe[:canceled_at]),
        past_due_since: past_due_since(previous_status)
      )

      @subscription.save!
      apply_to_printer

      warn_about_payment(previous_status)
      @subscription
    end

    private
      def status
        value = @stripe[:status].to_s
        Subscription::STATUSES.include?(value) ? value : "incomplete"
      end

      # The price decides the plan: a shop that upgrades through the Stripe
      # portal never touches our forms, and the webhook is how we find out.
      def plan_from_price
        price_id = @stripe.dig(:items, :data, 0, :price, :id)
        return nil if price_id.blank?

        Subscription::PLANS.find { |plan| StripeClient.price_for(plan) == price_id }
      end

      # Set the first time the status becomes past_due, and cleared as soon as
      # it is not. Counting the grace period from the sweep that noticed would
      # hand a shop extra days for nothing.
      def past_due_since(previous_status)
        return nil unless status == "past_due"
        return @subscription.past_due_since if previous_status == "past_due" &&
                                               @subscription.past_due_since.present?

        Time.current
      end

      # `featured` lives on the listing because that is what the directory
      # orders by; the subscription is what decides its value.
      def apply_to_printer
        @subscription.printer.update!(featured: @subscription.featured?)
      end

      # Told once, when the payment first fails — not on every webhook that
      # repeats the same status.
      def warn_about_payment(previous_status)
        return unless @subscription.past_due? && previous_status != "past_due"

        SubscriptionMailer.payment_failed(@subscription).deliver_later
      end

      def timestamp(value) = value.present? ? Time.zone.at(value.to_i) : nil
  end
end
