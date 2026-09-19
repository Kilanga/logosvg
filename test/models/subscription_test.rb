require "test_helper"

class SubscriptionTest < ActiveSupport::TestCase
  test "a paid subscription makes the listing visible" do
    assert_predicate subscriptions(:rennes), :visible?
    assert_predicate subscriptions(:nantes), :visible?, "a trial is paid for too"
  end

  test "an unfinished or cancelled subscription does not" do
    %w[ incomplete canceled ].each do |status|
      subscriptions(:rennes).update!(status: status)

      assert_not_predicate subscriptions(:rennes), :visible?
    end
  end

  # A card that stops working does not pull a shop off the directory the same
  # day: it keeps its listing while it sorts the card out.
  test "a failed payment keeps the listing up for the grace period" do
    subscriptions(:rennes).update!(status: "past_due", past_due_since: 2.days.ago)

    assert_predicate subscriptions(:rennes), :visible?
    assert_predicate subscriptions(:rennes), :within_grace?
  end

  test "and takes it down once the grace period is over" do
    subscriptions(:rennes).update!(status: "past_due", past_due_since: 10.days.ago)

    assert_not_predicate subscriptions(:rennes), :visible?
  end

  test "the date the listing goes dark is counted from the failure, not from today" do
    failed_at = 3.days.ago
    subscriptions(:rennes).update!(status: "past_due", past_due_since: failed_at)

    expected = failed_at + Rails.application.config.tshirt.subscriptions[:past_due_grace_days].days

    assert_in_delta expected, subscriptions(:rennes).hidden_from, 1.second
  end

  test "a healthy subscription has no date to go dark" do
    assert_nil subscriptions(:rennes).hidden_from
  end

  # Atelier+ buys the highlight — and only while it is being paid for.
  test "the highlight follows the plan and the payment together" do
    assert_predicate subscriptions(:lyon), :featured?
    assert_not_predicate subscriptions(:rennes), :featured?, "listing is not Atelier+"

    subscriptions(:lyon).update!(status: "canceled")

    assert_not_predicate subscriptions(:lyon), :featured?
  end
end

# The completion criterion of step 6, asked of the one scope that answers it.
class PrinterVisibilityTest < ActiveSupport::TestCase
  test "a published shop with a paid subscription is listed" do
    assert_includes Printer.listed, printers(:rennes)
    assert_includes Printer.listed, printers(:lyon)
  end

  test "a shop with no subscription at all appears nowhere" do
    subscriptions(:rennes).destroy

    assert_not_includes Printer.listed, printers(:rennes)
  end

  test "a shop whose subscription lapsed appears nowhere" do
    subscriptions(:rennes).update!(status: "canceled")

    assert_not_includes Printer.listed, printers(:rennes)
  end

  test "a shop in its grace period is still listed" do
    subscriptions(:rennes).update!(status: "past_due", past_due_since: 1.day.ago)

    assert_includes Printer.listed, printers(:rennes)
  end

  test "a shop past its grace period is not" do
    subscriptions(:rennes).update!(status: "past_due", past_due_since: 30.days.ago)

    assert_not_includes Printer.listed, printers(:rennes)
  end

  # A past_due with no recorded date is treated as just failed rather than as
  # long gone: the shop gets the benefit of the doubt for a few days.
  test "a past_due with no recorded date keeps the benefit of the doubt" do
    subscriptions(:rennes).update!(status: "past_due", past_due_since: nil)

    assert_includes Printer.listed, printers(:rennes)
  end

  # Paying does not publish a listing that has not been reviewed.
  test "paying does not put an unreviewed listing in the directory" do
    assert_not_includes Printer.listed, printers(:attente)
    assert_predicate subscriptions(:attente), :visible?
  end
end
