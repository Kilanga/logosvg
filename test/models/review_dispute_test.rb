require "test_helper"

# Decided on 08/10/2026: a client can say a delivery does not do what was
# asked. Every transition of the dispute, including the ones that must not
# happen.
class ReviewDisputeTest < ActiveSupport::TestCase
  setup { @review = reviews(:delivered) }

  test "a delivered review can be disputed, once, and the date is kept" do
    assert @review.may_dispute?
    @review.dispute!

    assert_predicate @review, :disputed?
    assert_not_nil @review.disputed_at
  end

  test "a review disputed before cannot be disputed again" do
    @review.dispute!
    @review.withdraw_dispute!

    assert_predicate @review, :delivered?
    assert_not @review.may_dispute?
    assert_raises(AASM::InvalidTransition) { @review.dispute! }
  end

  test "only a delivered review can be disputed" do
    %i[ queued in_progress returned ].each do |fixture|
      review = reviews(fixture)

      assert_not review.may_dispute?, "#{fixture} must not be disputable"
      assert_raises(AASM::InvalidTransition) { review.dispute! }
    end
  end

  test "a custom job, settled outside the platform, cannot be disputed here" do
    @review.review_level = review_levels(:custom)

    assert_not @review.may_dispute?
  end

  test "a fix can be accepted only once it was offered, and gives one more go" do
    @review.dispute!

    assert_not @review.may_accept_fix?
    assert_raises(AASM::InvalidTransition) { @review.accept_fix! }

    @review.fix_offered_at = Time.current
    before = @review.revisions_left
    @review.accept_fix!

    assert_predicate @review, :in_progress?
    assert_equal before, @review.revisions_left, "the extra go is used by the fix itself"
    assert @review.due_at.future?
  end

  test "withdrawing gives the client a fresh week" do
    @review.update!(delivered_at: 6.days.ago, acceptance_reminders_sent: 2)
    @review.dispute!
    @review.withdraw_dispute!

    assert_predicate @review, :delivered?
    assert @review.delivered_at > 1.minute.ago
    assert_equal 0, @review.acceptance_reminders_sent
  end

  test "a disputed review can be accepted, or cancelled by an administrator" do
    @review.dispute!
    assert @review.may_accept?
    assert @review.may_cancel?

    assert_not @review.may_deliver?
    assert_not @review.may_request_revision?
    assert_raises(AASM::InvalidTransition) { @review.request_revision! }
  end

  test "a new delivery resets the reminders" do
    review = reviews(:in_progress)
    review.acceptance_reminders_sent = 2
    review.deliver!

    assert_equal 0, review.acceptance_reminders_sent
  end

  # The commission applies to what is paid, at the review's own rate.
  test "the designer's share after a partial refund keeps the review's rate" do
    # 19 € paid, 3,80 € commission (20 %). 9 € refunded: 10 € kept, 2 € commission.
    assert_equal 800, @review.payout_after_refund(900)
    assert_equal 1520, @review.payout_after_refund(0)
    assert_equal 0, @review.payout_after_refund(1900)
  end

  test "the payout is the full share unless an administrator decided otherwise" do
    assert_equal @review.designer_share_cents, @review.payout_cents

    @review.designer_payout_cents = 500
    assert_equal 500, @review.payout_cents
  end
end
