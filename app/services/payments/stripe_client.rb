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

    # The second endpoint, for events from the designers' connected accounts
    # (`account.updated`). Stripe gives it a signing secret of its own, on the
    # same URL. Optional: without it, only the designers' payout status stops
    # following Stripe.
    def self.connect_webhook_secret
      ENV["STRIPE_CONNECT_WEBHOOK_SECRET"].presence ||
        Rails.application.credentials.dig(:stripe, :connect_webhook_secret)
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
    # The VAT rate applied on top of the plan's price, which is set excluding
    # tax: a Stripe Tax Rate id (20 %, exclusive), kept with the other ids.
    # Absent, the subscription is billed without VAT — fine in test mode,
    # wrong in production for a VAT-registered seller.
    def self.tax_rate
      ENV["STRIPE_TAX_RATE"].presence || Rails.application.credentials.dig(:stripe, :tax_rate)
    end

    def create_checkout_session(customer:, customer_email:, price:, success_url:, cancel_url:,
                                client_reference_id:, trial_days: nil, idempotency_key:)
      subscription_data = {
        trial_period_days: (trial_days if trial_days.to_i.positive?),
        default_tax_rates: ([ self.class.tax_rate ] if self.class.tax_rate.present?)
      }.compact.presence

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
          # Workshops are businesses: their VAT number goes on the invoice.
          tax_id_collection: { enabled: true },
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

    # --- Reviews --------------------------------------------------------------
    #
    # Charged on the platform's own account, then transferred to the designer
    # once the client accepts: separate charges and transfers, so a review that
    # is refunded never became the designer's money in the first place.

    def create_payment_session(amount_cents:, product_name:, client_email:,
                               success_url:, cancel_url:, client_reference_id:,
                               metadata: {}, idempotency_key:)
      request(idempotency_key) do
        @stripe.v1.checkout.sessions.create({
          mode: "payment",
          line_items: [ {
            quantity: 1,
            price_data: {
              currency: "eur",
              unit_amount: amount_cents,
              product_data: { name: product_name }
            }
          } ],
          customer_email: client_email,
          client_reference_id: client_reference_id,
          metadata: metadata,
          success_url: success_url,
          cancel_url: cancel_url
        }, { idempotency_key: idempotency_key })
      end
    end

    # The designer's share, moved to their Connect account.
    def create_transfer(amount_cents:, destination:, source_transaction: nil, idempotency_key:)
      request(idempotency_key) do
        @stripe.v1.transfers.create({
          amount: amount_cents, currency: "eur",
          destination: destination, source_transaction: source_transaction
        }.compact, { idempotency_key: idempotency_key })
      end
    end

    # What a payment brought in, and the charge behind it: a transfer tied to
    # that charge goes through once the money has arrived, instead of being
    # refused while the platform's balance is still pending.
    def retrieve_payment_intent(id)
      request(nil) { @stripe.v1.payment_intents.retrieve(id).to_hash }
    end

    def create_refund(payment_intent:, amount_cents: nil, idempotency_key:)
      request(idempotency_key) do
        @stripe.v1.refunds.create(
          { payment_intent: payment_intent, amount: amount_cents }.compact,
          { idempotency_key: idempotency_key }
        )
      end
    end

    # --- Connect Express ------------------------------------------------------
    #
    # Express because the platform has no business holding a designer's identity
    # documents or bank details: Stripe hosts the whole onboarding and hands
    # back one boolean, `payouts_enabled`.

    def create_connect_account(email:)
      request(nil) do
        @stripe.v1.accounts.create(
          type: "express", email: email, country: "FR",
          capabilities: { transfers: { requested: true } },
          business_type: "individual"
        )
      end
    end

    # Single-use and short-lived, by Stripe's design: a fresh one is minted
    # every time the designer starts or resumes onboarding.
    def create_account_link(account:, return_url:, refresh_url:)
      request(nil) do
        @stripe.v1.account_links.create(
          account: account, type: "account_onboarding",
          return_url: return_url, refresh_url: refresh_url
        )
      end
    end

    # Where a designer reads their own payouts. Also Stripe-hosted.
    def create_login_link(account:)
      request(nil) { @stripe.v1.accounts.login_links.create(account) }
    end

    def retrieve_account(id)
      request(nil) { @stripe.v1.accounts.retrieve(id).to_hash }
    end

    # Verifies the signature and returns the event. An unsigned or missigned
    # payload never becomes an event at all.
    #
    # Two endpoints share the URL, each signing with its own secret: the
    # platform's, and the connected accounts'. A payload is accepted if either
    # signs it.
    def self.decode_webhook(payload:, signature:)
      raise NotConfigured, "STRIPE_WEBHOOK_SECRET is not set" if webhook_secret.blank?

      secrets = [ webhook_secret, connect_webhook_secret ].compact_blank
      secrets.each_with_index do |secret, index|
        return Stripe::Webhook.construct_event(payload, signature, secret)
      rescue Stripe::SignatureVerificationError
        raise if index == secrets.size - 1
      end
    end

    private
      def request(_idempotency_key)
        yield
      rescue Stripe::StripeError => e
        raise Failed, "#{e.class}: #{e.message}"
      end
  end
end
