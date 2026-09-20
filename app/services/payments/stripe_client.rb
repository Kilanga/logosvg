module Payments
  # The only object in the application that talks to Stripe.
  #
  # Everything else asks this for a session or hands it an event; nothing else
  # knows the gem exists. That is what lets the whole subscription flow be
  # tested against a stand-in, and what will make a change of provider a change
  # in one directory.
  class StripeClient
    # The keys are missing. A configuration fault, never the shop's, and never
    # something to explain to them in Stripe's words.
    NotConfigured = Class.new(StandardError)
    # Stripe answered, and said no. Carries its own message for the log.
    Failed = Class.new(StandardError)

    def self.configured? = secret_key.present?

    def self.secret_key
      ENV["STRIPE_SECRET_KEY"].presence || Rails.application.credentials.dig(:stripe, :secret_key)
    end

    def self.publishable_key
      ENV["STRIPE_PUBLISHABLE_KEY"].presence ||
        Rails.application.credentials.dig(:stripe, :publishable_key)
    end

    def self.webhook_secret
      ENV["STRIPE_WEBHOOK_SECRET"].presence ||
        Rails.application.credentials.dig(:stripe, :webhook_secret)
    end

    # The price ids for the two plans. Never in settings.yml: they identify
    # billable objects in an account, and belong with the secrets.
    def self.price_for(plan)
      case plan.to_s
      when "listing" then ENV["STRIPE_PRICE_LISTING"].presence
      when "atelier_plus" then ENV["STRIPE_PRICE_ATELIER_PLUS"].presence
      end || Rails.application.credentials.dig(:stripe, :"price_#{plan}")
    end

    def initialize
      raise NotConfigured, "STRIPE_SECRET_KEY is not set" unless self.class.configured?

      @stripe = Stripe::StripeClient.new(self.class.secret_key)
    end

    # Every call carries an idempotency key: Stripe retries on its own, and so
    # do we, and neither must bill a shop twice.
    def create_checkout_session(customer:, customer_email:, price:, success_url:, cancel_url:,
                                client_reference_id:, trial_days: nil, idempotency_key:)
      subscription_data = { trial_period_days: trial_days } if trial_days.to_i.positive?

      request(idempotency_key) do
        @stripe.v1.checkout.sessions.create({
          mode: "subscription",
          line_items: [ { price: price, quantity: 1 } ],
          customer: customer,
          customer_email: (customer_email if customer.blank?),
          # Our own printer id, handed back on the first webhook. Without it a
          # brand-new subscription arrives with a customer we have never seen.
          client_reference_id: client_reference_id,
          subscription_data: subscription_data,
          success_url: success_url,
          cancel_url: cancel_url
        }.compact, { idempotency_key: idempotency_key })
      end
    end

    # The portal is where a shop changes plan, card and reads its invoices. We
    # deliberately build none of that ourselves.
    def create_portal_session(customer:, return_url:)
      request(nil) do
        @stripe.v1.billing_portal.sessions.create(customer: customer, return_url: return_url)
      end
    end

    # Handed back as a plain hash. Everything downstream then deals with one
    # shape whether it came from the network or from a test.
    def retrieve_subscription(id)
      request(nil) { @stripe.v1.subscriptions.retrieve(id).to_hash }
    end

    # Verifies the signature and returns the event. An unsigned or missigned
    # payload never becomes an event at all.
    def self.decode_webhook(payload:, signature:)
      raise NotConfigured, "STRIPE_WEBHOOK_SECRET is not set" if webhook_secret.blank?

      Stripe::Webhook.construct_event(payload, signature, webhook_secret)
    end

    private
      def request(_idempotency_key)
        yield
      rescue Stripe::StripeError => e
        raise Failed, "#{e.class}: #{e.message}"
      end
  end
end
