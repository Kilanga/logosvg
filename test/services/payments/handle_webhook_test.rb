require "test_helper"

module Payments
  class HandleWebhookTest < ActiveSupport::TestCase
    setup do
      ENV["STRIPE_SECRET_KEY"] = "sk_test_not_a_real_key_placeholder"
      ENV["STRIPE_PRICE_LISTING"] = "price_listing_test"
      ENV["STRIPE_PRICE_ATELIER_PLUS"] = "price_atelier_plus_test"
    end

    teardown do
      %w[ STRIPE_SECRET_KEY STRIPE_PRICE_LISTING STRIPE_PRICE_ATELIER_PLUS ].each { |k| ENV.delete(k) }
    end

    # Stripe retries deliveries freely. The event id, behind a unique index, is
    # what makes handling one safe to repeat.
    test "the same event is acted on once and only once" do
      stub_subscription_fetch(status: "active")

      assert_equal :processed, handle(event("evt_1", "customer.subscription.updated"))
      assert_equal :duplicate, handle(event("evt_1", "customer.subscription.updated"))

      assert_equal 1, StripeEvent.where(stripe_id: "evt_1").count
    end

    test "a duplicate is not an error: Stripe must not be asked to try again" do
      stub_subscription_fetch(status: "active")
      handle(event("evt_2", "customer.subscription.updated"))

      assert_nothing_raised { handle(event("evt_2", "customer.subscription.updated")) }
    end

    test "every event is recorded, and a handled one is marked as such" do
      stub_subscription_fetch(status: "active")

      handle(event("evt_3", "customer.subscription.updated"))

      assert_not_nil StripeEvent.find_by(stripe_id: "evt_3").processed_at
    end

    test "a subscription update reaches the row" do
      stub_subscription_fetch(status: "past_due")

      handle(event("evt_4", "customer.subscription.updated",
                   object: stripe_subscription(status: "past_due")))

      assert_predicate subscriptions(:rennes).reload, :past_due?
    end

    # The first webhook of a new subscription carries the customer id we had no
    # way of knowing before.
    test "a completed checkout stores the customer and syncs the subscription" do
      subscriptions(:rennes).update!(stripe_customer_id: nil, stripe_subscription_id: nil)
      stub_subscription_fetch(status: "active", id: "sub_brand_new", customer: "cus_brand_new")

      handle(event("evt_5", "checkout.session.completed", object: {
        id: "cs_test", customer: "cus_brand_new", subscription: "sub_brand_new",
        client_reference_id: printers(:rennes).id.to_s
      }))

      assert_equal "cus_brand_new", subscriptions(:rennes).reload.stripe_customer_id
      assert_predicate subscriptions(:rennes), :active?
    end

    test "a failed invoice re-reads the subscription rather than guessing from it" do
      stub_subscription_fetch(status: "past_due")

      handle(event("evt_6", "invoice.payment_failed", object: {
        id: "in_test", customer: "cus_test_rennes", subscription: "sub_test_rennes"
      }))

      assert_predicate subscriptions(:rennes).reload, :past_due?
      assert_requested :get, %r{/v1/subscriptions/sub_test_rennes}
    end

    test "an event we do not handle is recorded and left alone" do
      assert_equal :processed, handle(event("evt_7", "customer.created"))
      assert_not_nil StripeEvent.find_by(stripe_id: "evt_7").processed_at
    end

    # A customer we have never seen is not a reason to raise: Stripe accounts
    # carry objects that have nothing to do with us.
    test "an event about a subscription we do not know is ignored quietly" do
      assert_nothing_raised do
        handle(event("evt_8", "customer.subscription.updated",
                     object: { id: "sub_someone_else", customer: "cus_someone_else", status: "active" }))
      end
    end

    # The failure is kept so it can be found again.
    test "a failure is recorded on the event and re-raised" do
      stub_request(:get, %r{/v1/subscriptions/}).to_return(status: 500, body: "{}")

      assert_raises(StripeClient::Failed) do
        handle(event("evt_9", "invoice.paid", object: {
          id: "in_test", customer: "cus_test_rennes", subscription: "sub_test_rennes"
        }))
      end

      assert_predicate StripeEvent.find_by(stripe_id: "evt_9").error_message, :present?
    end

    private
      def handle(payload) = HandleWebhook.call(event: payload)

      def event(id, type, object: stripe_subscription)
        { id: id, type: type, data: { object: object } }
      end

      def stripe_subscription(status: "active", id: "sub_test_rennes", customer: "cus_test_rennes")
        { id: id, customer: customer, status: status,
          current_period_end: 1.month.from_now.to_i,
          items: { data: [ { price: { id: "price_listing_test" } } ] } }
      end

      def stub_subscription_fetch(status:, id: "sub_test_rennes", customer: "cus_test_rennes")
        stub_request(:get, %r{/v1/subscriptions/}).to_return(
          headers: { "Content-Type" => "application/json" },
          body: stripe_subscription(status: status, id: id, customer: customer).to_json
        )
      end
  end
end
