require "test_helper"

module Payments
  # The prices are set excluding VAT (decided on 06/10/2026: the seller is
  # VAT-registered, and workshops are businesses). The rate is added by
  # Stripe, from a Tax Rate id kept with the other ids.
  class StripeClientTest < ActiveSupport::TestCase
    CHECKOUT = "https://api.stripe.com/v1/checkout/sessions".freeze

    setup do
      ENV["STRIPE_SECRET_KEY"] = "sk_test_placeholder"
      stub_request(:post, CHECKOUT)
                    .to_return(status: 200, body: { id: "cs_test", url: "https://checkout.stripe.test" }.to_json)
    end

    teardown { %w[ STRIPE_SECRET_KEY STRIPE_TAX_RATE ].each { |key| ENV.delete(key) } }

    test "a subscription checkout adds the VAT rate and asks for the VAT number" do
      ENV["STRIPE_TAX_RATE"] = "txr_tva20"

      open_session

      assert_requested :post, CHECKOUT do |request|
        body = Rack::Utils.parse_nested_query(request.body)
        body.dig("subscription_data", "default_tax_rates", "0") == "txr_tva20" &&
          body.dig("subscription_data", "trial_period_days") == "30" &&
          body.dig("tax_id_collection", "enabled") == "true"
      end
    end

    test "without a rate configured, no tax line is sent" do
      open_session

      assert_requested :post, CHECKOUT do |request|
        Rack::Utils.parse_nested_query(request.body).dig("subscription_data", "default_tax_rates").nil?
      end
    end

    # 09/10/2026: a shop that had opened Checkout the day before could not open
    # it again once the VAT rate was set — same key, other parameters, and
    # Stripe refuses that for a day.
    test "the same request twice carries the same key; a changed one, another" do
      keys = []
      stub_request(:post, CHECKOUT).with { |request| keys << request.headers["Idempotency-Key"] }
                                   .to_return(status: 200, body: { id: "cs_test", url: "https://checkout.stripe.test" }.to_json)

      2.times { open_session(key: "checkout-1-listing-42") }
      ENV["STRIPE_TAX_RATE"] = "txr_tva20"
      open_session(key: "checkout-1-listing-42")

      assert_equal 3, keys.size
      assert_equal keys[0], keys[1]
      assert_not_equal keys[1], keys[2]
      assert keys.all? { |key| key.start_with?("checkout-1-listing-42-") }
    end

    private
      def open_session(key: "test-#{SecureRandom.hex(4)}")
        StripeClient.new.create_checkout_session(
          customer: nil, customer_email: "atelier@example.com", price: "price_listing",
          success_url: "https://example.com/ok", cancel_url: "https://example.com/ko",
          client_reference_id: "1", trial_days: 30, idempotency_key: key
        )
      end
  end
end
