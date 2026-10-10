require "test_helper"

class MailDeliveryDayTest < ActiveSupport::TestCase
  test "recipients and failures add up on today's row" do
    MailDeliveryDay.record_sent!(2)
    MailDeliveryDay.record_sent!(3)
    MailDeliveryDay.record_failed!

    today = MailDeliveryDay.today
    assert_equal 5, today.recipients_count
    assert_equal 1, today.failed_count
    assert_equal 1, MailDeliveryDay.count
  end

  test "a new day starts from nothing" do
    MailDeliveryDay.record_sent!(4)

    travel 1.day do
      assert_equal 0, MailDeliveryDay.today.recipients_count
      assert_predicate MailDeliveryDay.today, :new_record?
    end
  end

  test "the alert comes at 80 % of the daily limit" do
    assert_not MailDeliveryDay.new(recipients_count: 239).near_limit?
    assert_predicate MailDeliveryDay.new(recipients_count: 240), :near_limit?
  end
end
