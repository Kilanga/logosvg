require "test_helper"

module Payments
  # Charges and transfers are separate: the money sits on the platform's
  # account until the client is satisfied.
  class SettleReviewTest < ActiveSupport::TestCase
    setup { ENV["STRIPE_SECRET_KEY"] = "sk_test_not_a_real_key_placeholder" }
    teardown { ENV.delete("STRIPE_SECRET_KEY") }

    test "an accepted review transfers the designer's share" do
      stub_transfer
      review = accepted_review

      assert_equal :transferred, SettleReview.call(review: review)
      assert_equal "tr_test_1", review.reload.stripe_transfer_id

      assert_requested :post, %r{/v1/transfers} do |request|
        body = Rack::Utils.parse_nested_query(request.body)
        body["amount"] == "1520" && body["destination"] == "acct_test_ines"
      end
    end

    # A retried webhook, or an administrator pressing twice, must not pay twice.
    test "a review already settled is not paid again" do
      stub_transfer
      review = accepted_review
      SettleReview.call(review: review)

      assert_equal :already_settled, SettleReview.call(review: review.reload)
      assert_requested :post, %r{/v1/transfers}, times: 1
    end

    test "a review that is not accepted transfers nothing" do
      assert_equal :not_accepted, SettleReview.call(review: reviews(:delivered))
      assert_not_requested :post, %r{/v1/transfers}
    end

    test "a designer with no Stripe account is not paid" do
      # Cleared before the review is loaded: the association is memoised, and
      # emptying it afterwards would leave the old value in hand.
      designer_profiles(:ines).update!(stripe_account_id: nil)

      assert_equal :no_destination, SettleReview.call(review: accepted_review)
      assert_not_requested :post, %r{/v1/transfers}
    end

    # Left for a human rather than retried blindly.
    test "a refused transfer is reported rather than raising" do
      stub_request(:post, %r{/v1/transfers}).to_return(status: 400, body: "{}")

      assert_equal :failed, SettleReview.call(review: accepted_review)
    end

    test "the designer is told they have been paid" do
      stub_transfer

      assert_emails 1 do
        SettleReview.call(review: accepted_review)
        perform_enqueued_jobs
      end
    end

    private
      def accepted_review
        reviews(:delivered).tap do |review|
          review.accept!
          review.save!
        end
      end

      def stub_transfer
        stub_request(:post, %r{/v1/transfers}).to_return(
          headers: { "Content-Type" => "application/json" },
          body: { id: "tr_test_1", object: "transfer", amount: 1520 }.to_json
        )
      end
  end

  class RefundReviewTest < ActiveSupport::TestCase
    setup { ENV["STRIPE_SECRET_KEY"] = "sk_test_not_a_real_key_placeholder" }
    teardown { ENV.delete("STRIPE_SECRET_KEY") }

    test "a refund goes back to the client and is recorded" do
      stub_refund

      assert_equal :refunded, RefundReview.call(review: reviews(:delivered))
      assert_equal 1900, reviews(:delivered).reload.refunded_cents
    end

    # Refunding what was already refunded is the failure this guards against.
    test "nothing beyond the price ever leaves" do
      stub_refund
      RefundReview.call(review: reviews(:delivered))

      assert_equal :nothing_to_refund, RefundReview.call(review: reviews(:delivered).reload)
      assert_requested :post, %r{/v1/refunds}, times: 1
    end

    test "a partial refund leaves the rest available" do
      stub_refund
      RefundReview.call(review: reviews(:delivered), amount_cents: 500)

      assert_equal 500, reviews(:delivered).reload.refunded_cents

      RefundReview.call(review: reviews(:delivered), amount_cents: 5000)

      assert_equal 1900, reviews(:delivered).reload.refunded_cents,
                   "capped at what is left, not at what was asked"
    end

    test "a review that was never paid refunds nothing" do
      reviews(:delivered).update!(stripe_payment_intent_id: nil)

      assert_equal :not_paid, RefundReview.call(review: reviews(:delivered))
    end

    test "the client is told" do
      stub_refund

      assert_emails 1 do
        RefundReview.call(review: reviews(:delivered))
        perform_enqueued_jobs
      end
    end

    private
      def stub_refund
        stub_request(:post, %r{/v1/refunds}).to_return(
          headers: { "Content-Type" => "application/json" },
          body: { id: "re_test_1", object: "refund" }.to_json
        )
      end
  end
end
