require "test_helper"

module Payments
  # Stripe is the authority on status and dates. What this object owns is the
  # consequences: visibility, the highlight, and when a payment first failed.
  class SyncSubscriptionTest < ActiveSupport::TestCase
    setup do
      ENV["STRIPE_PRICE_LISTING"] = "price_listing_test"
      ENV["STRIPE_PRICE_ATELIER_PLUS"] = "price_atelier_plus_test"
    end

    teardown do
      %w[ STRIPE_PRICE_LISTING STRIPE_PRICE_ATELIER_PLUS ].each { |k| ENV.delete(k) }
    end

    test "the status and the period end come from Stripe, as they are" do
      ends_at = 10.days.from_now

      sync(status: "active", current_period_end: ends_at.to_i)

      assert_predicate subscription.reload, :active?
      assert_in_delta ends_at, subscription.current_period_end, 1.second
    end

    # A shop that upgrades through Stripe's portal never touches our forms.
    test "the plan follows the price, so an upgrade made at Stripe is noticed" do
      assert_predicate subscription, :listing?

      sync(status: "active", price_id: "price_atelier_plus_test")

      assert_predicate subscription.reload, :atelier_plus?
    end

    test "a price we do not know leaves the plan alone rather than guessing" do
      sync(status: "active", price_id: "price_something_else")

      assert_predicate subscription.reload, :listing?
    end

    # `featured` lives on the listing because that is what the directory orders
    # by; the subscription decides its value.
    test "the highlight is applied to the listing" do
      sync(status: "active", price_id: "price_atelier_plus_test")

      assert_predicate printers(:rennes).reload, :featured?

      sync(status: "canceled", price_id: "price_atelier_plus_test")

      assert_not_predicate printers(:rennes).reload, :featured?
    end

    test "the moment a payment first failed is recorded" do
      freeze_time do
        sync(status: "past_due")

        assert_in_delta Time.current, subscription.reload.past_due_since, 1.second
      end
    end

    # Counting the grace period from the last webhook would hand a shop extra
    # days every time Stripe repeated itself.
    test "a repeated past_due does not restart the grace period" do
      first_failure = 3.days.ago
      subscription.update!(status: "past_due", past_due_since: first_failure)

      sync(status: "past_due")

      assert_in_delta first_failure, subscription.reload.past_due_since, 1.second
    end

    test "recovering clears the failure date" do
      subscription.update!(status: "past_due", past_due_since: 2.days.ago)

      sync(status: "active")

      assert_nil subscription.reload.past_due_since
    end

    test "the shop is told once, the first time the payment fails" do
      assert_emails 1 do
        sync(status: "past_due")
      end

      assert_no_emails { sync(status: "past_due") }
    end

    test "a status Stripe invents is not copied in blindly" do
      sync(status: "something_new")

      assert_predicate subscription.reload, :incomplete?
    end

    private
      def subscription = subscriptions(:rennes)

      def sync(status:, price_id: "price_listing_test", current_period_end: 1.month.from_now.to_i)
        SyncSubscription.call(
          subscription: subscription,
          stripe_subscription: {
            id: "sub_test_rennes", customer: "cus_test_rennes", status: status,
            current_period_end: current_period_end,
            items: { data: [ { price: { id: price_id } } ] }
          }
        )
      end
  end
end
