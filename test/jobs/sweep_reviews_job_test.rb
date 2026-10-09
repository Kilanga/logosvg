require "test_helper"

class SweepReviewsJobTest < ActiveJob::TestCase
  # The sweep looks at every row, so a test counting emails has to say which
  # review it is about. The silent-designer fixture is stamped as already
  # reported unless the test at hand is the one about it.
  setup { reviews(:silent).update_column(:designer_reminded_at, Time.current) }

  # Seven days after the last delivery with no word from the client, the work
  # is taken as accepted and the designer is paid.
  test "a delivered review nobody answered is accepted for them" do
    reviews(:delivered).update!(delivered_at: 8.days.ago)

    SweepReviewsJob.perform_now

    assert_predicate reviews(:delivered).reload, :accepted?
    assert_not_nil reviews(:delivered).accepted_at
  end

  test "a review delivered yesterday is left alone" do
    SweepReviewsJob.perform_now

    assert_predicate reviews(:delivered).reload, :delivered?
  end

  # A proposal nobody answered is a refusal, and the money goes back.
  test "an expired proposal cancels the review" do
    reviews(:returned).update!(proposal_expires_at: 1.hour.ago)

    SweepReviewsJob.perform_now

    assert_predicate reviews(:returned).reload, :canceled?
  end

  test "a proposal still open is left alone" do
    SweepReviewsJob.perform_now

    assert_predicate reviews(:returned).reload, :returned_to_client?
  end

  # Chased once, a day before it lapses.
  test "a proposal about to lapse is chased, and only once" do
    reviews(:returned).update!(proposal_expires_at: 12.hours.from_now)

    SweepReviewsJob.perform_now
    # Drained here: `perform_enqueued_jobs` inside the assertion below would
    # otherwise deliver this first run's email and be counted against it.
    perform_enqueued_jobs

    assert_not_nil reviews(:returned).reload.proposal_reminded_at

    assert_no_emails do
      SweepReviewsJob.perform_now
      perform_enqueued_jobs
    end
  end

  # Expiry runs before the reminder: a proposal past its date must not be
  # chased and closed in the same minute.
  test "a proposal past its date is closed rather than chased" do
    reviews(:returned).update!(proposal_expires_at: 1.minute.ago)

    assert_emails 1 do
      SweepReviewsJob.perform_now
      perform_enqueued_jobs
    end

    assert_predicate reviews(:returned).reload, :canceled?
  end

  # The chosen designer has had twelve hours; the client decides what next.
  test "a silent chosen designer is reported to the client, once" do
    reviews(:silent).update_column(:designer_reminded_at, nil)

    SweepReviewsJob.perform_now
    perform_enqueued_jobs

    assert_not_nil reviews(:silent).reload.designer_reminded_at
    assert_predicate reviews(:silent), :queued?, "nothing is decided for the client"

    assert_no_emails do
      SweepReviewsJob.perform_now
      perform_enqueued_jobs
    end
  end

  test "a first-available review is never reported as silent" do
    SweepReviewsJob.perform_now

    assert_nil reviews(:queued).reload.designer_reminded_at
  end

  test "a review in progress is none of the sweep's business" do
    SweepReviewsJob.perform_now

    assert_predicate reviews(:in_progress).reload, :in_progress?
  end
  # --- Reminders before the automatic acceptance (decided on 08/10/2026) ---

  test "the client is reminded three days, then one day, before silence counts" do
    review = reviews(:delivered)

    review.update!(delivered_at: 4.days.ago - 1.minute)
    assert_emails(1) { SweepReviewsJob.perform_now; perform_enqueued_jobs }
    assert_equal 1, review.reload.acceptance_reminders_sent

    assert_emails(0) { SweepReviewsJob.perform_now; perform_enqueued_jobs }

    review.update!(delivered_at: 6.days.ago - 1.minute)
    assert_emails(1) { SweepReviewsJob.perform_now; perform_enqueued_jobs }
    assert_equal 2, review.reload.acceptance_reminders_sent
    assert_predicate review, :delivered?
  end

  test "a sweep that missed a run sends only the closest reminder" do
    reviews(:delivered).update!(delivered_at: 6.days.ago - 1.minute)

    assert_emails(1) { SweepReviewsJob.perform_now; perform_enqueued_jobs }
    assert_equal 2, reviews(:delivered).reload.acceptance_reminders_sent
  end

  test "nothing is sent on the first days" do
    reviews(:delivered).update!(delivered_at: 2.days.ago)

    assert_emails(0) { SweepReviewsJob.perform_now; perform_enqueued_jobs }
  end

  # --- Nobody took it (09/10/2026) -------------------------------------------

  test "a paid review nobody took in 48 hours is called off and refunded in full" do
    ENV["STRIPE_SECRET_KEY"] = "sk_test_not_a_real_key_placeholder"
    stub_request(:post, %r{/v1/refunds}).to_return(status: 200, body: { id: "re_1", status: "succeeded" }.to_json)
    review = reviews(:queued)
    review.update_column(:queued_at, 49.hours.ago)

    assert_enqueued_email_with ReviewMailer, :unclaimed, args: [ review ] do
      SweepReviewsJob.perform_now
    end

    assert_predicate review.reload, :canceled?
    assert_equal review.price_cents, review.refunded_cents
  ensure
    ENV.delete("STRIPE_SECRET_KEY")
  end

  test "a review queued yesterday is left to the designers" do
    review = reviews(:queued)
    review.update_column(:queued_at, 20.hours.ago)

    SweepReviewsJob.perform_now

    assert_predicate review.reload, :queued?
  end

  test "a refund that fails leaves the review in the queue, to be tried again" do
    ENV["STRIPE_SECRET_KEY"] = "sk_test_not_a_real_key_placeholder"
    stub_request(:post, %r{/v1/refunds}).to_return(status: 500, body: "{}")
    review = reviews(:queued)
    review.update_column(:queued_at, 49.hours.ago)

    SweepReviewsJob.perform_now

    assert_predicate review.reload, :queued?
  ensure
    ENV.delete("STRIPE_SECRET_KEY")
  end
end
