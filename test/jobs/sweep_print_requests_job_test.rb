require "test_helper"

class SweepPrintRequestsJobTest < ActiveJob::TestCase
  # A request left unanswered long enough is chased, then closed. `forgotten`
  # was sent nine days ago, so it is past both marks.
  test "a request past the expiry mark is closed and the client is told" do
    assert_emails 1 do
      SweepPrintRequestsJob.perform_now
      perform_enqueued_jobs
    end

    assert_predicate print_requests(:forgotten).reload, :expired?
  end

  test "a request just sent is left alone entirely" do
    print_requests(:forgotten).destroy

    assert_no_emails do
      SweepPrintRequestsJob.perform_now
      perform_enqueued_jobs
    end

    assert_predicate print_requests(:waiting).reload, :sent?
    assert_nil print_requests(:waiting).reload.reminded_at
  end

  test "a request past the reminder mark is chased once" do
    request = print_requests(:waiting)
    request.update!(sent_at: 3.days.ago)
    print_requests(:forgotten).destroy

    SweepPrintRequestsJob.perform_now

    assert_not_nil request.reload.reminded_at
    assert_predicate request, :sent?, "chasing does not change the state"
  end

  # `reminded_at` is the whole reason the sweep can run every hour.
  test "a request already chased is not chased again" do
    request = print_requests(:waiting)
    request.update!(sent_at: 3.days.ago, reminded_at: 1.day.ago)
    print_requests(:forgotten).destroy

    assert_no_emails do
      SweepPrintRequestsJob.perform_now
      perform_enqueued_jobs
    end

    assert_equal 1.day.ago.to_date, request.reload.reminded_at.to_date
  end

  # A workshop that answered an hour after being sent the job must not receive
  # a reminder two days later.
  test "a request the shop acknowledged is neither chased nor expired" do
    acknowledged = print_requests(:acknowledged)
    acknowledged.update!(sent_at: 9.days.ago)
    print_requests(:forgotten).destroy

    assert_no_emails do
      SweepPrintRequestsJob.perform_now
      perform_enqueued_jobs
    end

    assert_predicate acknowledged.reload, :acknowledged?
  end

  test "a canceled request is swept over, not expired" do
    print_requests(:forgotten).cancel!

    assert_no_emails do
      SweepPrintRequestsJob.perform_now
      perform_enqueued_jobs
    end

    assert_predicate print_requests(:forgotten).reload, :canceled?
  end
end
