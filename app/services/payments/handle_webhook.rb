module Payments
  # Acts on one Stripe event, at most once.
  #
  # Stripe retries deliveries freely — on a timeout, on a 500, sometimes simply
  # twice — so the event id is claimed behind a unique index before anything
  # happens. A delivery that loses that race is acknowledged and dropped.
  class HandleWebhook
    HANDLED = %w[
      checkout.session.completed
      customer.subscription.created
      customer.subscription.updated
      customer.subscription.deleted
      invoice.payment_failed
      invoice.paid
    ].freeze

    def self.call(...) = new(...).call

    def initialize(event:)
      @event = event
    end

    def call
      record = StripeEvent.claim(id: @event[:id], type: @event[:type])
      # Already seen. Stripe is told everything is fine: retrying would change
      # nothing, and a 500 here would make it retry for days.
      return :duplicate if record.nil?

      dispatch
      record.processed!
      :processed
    rescue StandardError => e
      record&.failed!(e.message)
      raise
    end

    private
      # The controller hands this a plain hash, so `dig` works the same whether
      # the event came from Stripe or from a test.
      def object = @event.dig(:data, :object) || {}

      def dispatch
        case @event[:type]
        when "checkout.session.completed" then complete_checkout
        when /\Acustomer\.subscription\./ then sync_from_event
        when "invoice.payment_failed", "invoice.paid" then sync_from_invoice
        else :ignored
        end
      end

      # The first webhook of a new subscription. It carries the customer id we
      # had no way of knowing before, so it is stored even if the rest of the
      # subscription arrives in a later event.
      def complete_checkout
        subscription = subscription_for_customer(object[:customer]) ||
                       subscription_for_client_reference(object[:client_reference_id])
        return if subscription.nil?

        subscription.update!(stripe_customer_id: object[:customer])
        sync(subscription, object[:subscription])
      end

      def sync_from_event
        subscription = find_subscription(object[:id], object[:customer])
        return if subscription.nil?

        SyncSubscription.call(subscription: subscription, stripe_subscription: object)
      end

      # An invoice says a payment succeeded or failed; the subscription itself
      # is what carries the resulting status, so it is re-read rather than
      # inferred from the invoice.
      def sync_from_invoice
        subscription = find_subscription(object[:subscription], object[:customer])
        return if subscription.nil? || object[:subscription].blank?

        sync(subscription, object[:subscription])
      end

      def sync(subscription, stripe_subscription_id)
        return if stripe_subscription_id.blank?

        remote = StripeClient.new.retrieve_subscription(stripe_subscription_id)
        SyncSubscription.call(subscription: subscription, stripe_subscription: remote)
      end

      def find_subscription(stripe_subscription_id, customer_id)
        (Subscription.find_by(stripe_subscription_id: stripe_subscription_id) if stripe_subscription_id.present?) ||
          subscription_for_customer(customer_id)
      end

      def subscription_for_customer(customer_id)
        Subscription.find_by(stripe_customer_id: customer_id) if customer_id.present?
      end

      # Set when the Checkout session was opened, as a last resort for the very
      # first event of a subscription.
      def subscription_for_client_reference(reference)
        Subscription.find_by(printer_id: reference) if reference.present?
      end
  end
end
