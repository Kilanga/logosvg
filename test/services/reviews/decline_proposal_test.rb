require "test_helper"

module Reviews
  # Decided on 15/10/2026: once a designer has taken the review on, part of the
  # price is theirs even when the client refuses what they propose.
  class DeclineProposalTest < ActiveSupport::TestCase
    setup do
      ENV["STRIPE_SECRET_KEY"] = "sk_test_not_a_real_key_placeholder"
      @refund = stub_request(:post, %r{/v1/refunds}).to_return(
        headers: { "Content-Type" => "application/json" }, body: { id: "re_1" }.to_json
      )
      stub_request(:get, %r{/v1/payment_intents/}).to_return(
        headers: { "Content-Type" => "application/json" },
        body: { id: "pi_test_returned", latest_charge: "ch_1", amount_received: 1900 }.to_json
      )
      @transfer = stub_request(:post, %r{/v1/transfers})
                  .to_return(headers: { "Content-Type" => "application/json" }, body: { id: "tr_1" }.to_json)
    end
    teardown { ENV.delete("STRIPE_SECRET_KEY") }

    test "handed back from the queue, the review is refunded in full and pays nobody" do
      review = DeclineProposal.call(review: reviews(:returned))

      assert_predicate review, :canceled?
      assert_equal 1900, review.refunded_cents
      assert_nil review.designer_payout_cents
      assert_not_requested @transfer
    end

    test "handed back after the designer took it on, the guaranteed share is paid out" do
      reviews(:returned).update_column(:claimed_at, 2.days.ago)

      review = DeclineProposal.call(review: reviews(:returned))

      # 30 % of 19 € = 5,70 € kept; less the 20 % commission, 4,56 € paid.
      assert_equal 1330, review.refunded_cents
      assert_equal 456, review.designer_payout_cents
      assert_requested :post, %r{/v1/transfers} do |request|
        Rack::Utils.parse_nested_query(request.body)["amount"] == "456"
      end
    end

    test "the designer is told the review is closed" do
      assert_emails 2 do
        DeclineProposal.call(review: reviews(:returned))
        perform_enqueued_jobs
      end

      assert(ActionMailer::Base.deliveries.any? { |mail| mail.to == [ users(:designer).email_address ] })
    end

    # The way out offered when the chosen designer went quiet.
    test "a review whose chosen designer never answered is called off and refunded" do
      review = DeclineProposal.call(review: reviews(:silent))

      assert_predicate review, :canceled?
      assert_equal 1900, review.refunded_cents
    end
  end
end
