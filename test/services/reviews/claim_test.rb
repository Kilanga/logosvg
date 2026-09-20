require "test_helper"

module Reviews
  class ClaimTest < ActiveSupport::TestCase
    test "a designer who can do it takes it, and gets a deadline" do
      result = Claim.call(review: reviews(:queued), profile: designer_profiles(:ines))

      assert_predicate result, :success?

      review = reviews(:queued).reload

      assert_predicate review, :in_progress?
      assert_equal designer_profiles(:ines), review.designer_profile
      assert_in_delta review.review_level.turnaround_hours.hours.from_now, review.due_at, 5.seconds
    end

    # Two designers press the button in the same second. The lock is what makes
    # exactly one of them win.
    test "a review already taken cannot be taken again" do
      Claim.call(review: reviews(:queued), profile: designer_profiles(:ines))

      result = Claim.call(review: reviews(:queued).reload, profile: designer_profiles(:tom))

      assert_not_predicate result, :success?
      assert_equal designer_profiles(:ines), reviews(:queued).reload.designer_profile
    end

    # The rule step 7 exists for, enforced where the work changes hands.
    test "a designer Stripe cannot pay takes nothing" do
      result = Claim.call(review: reviews(:queued), profile: designer_profiles(:leo))

      assert_not_predicate result, :success?
      assert_equal I18n.t("designers.unavailable.payouts_disabled"), result.error
      assert_predicate reviews(:queued).reload, :queued?
    end

    test "an unvetted designer takes nothing" do
      result = Claim.call(review: reviews(:queued), profile: designer_profiles(:nour))

      assert_not_predicate result, :success?
      assert_predicate reviews(:queued).reload, :queued?
    end

    # Inès is available in every other respect, so the level is what refuses
    # her — the reasons are checked in the order that decides fastest, and a
    # designer on holiday would be turned away before this one ever ran.
    test "a designer who does not accept the level takes nothing" do
      reviews(:queued).update!(review_level: review_levels(:custom))
      designer_profiles(:ines).review_levels.destroy(review_levels(:custom))

      result = Claim.call(review: reviews(:queued), profile: designer_profiles(:ines).reload)

      assert_not_predicate result, :success?
      assert_equal I18n.t("reviews.errors.level_not_accepted"), result.error
      assert_predicate reviews(:queued).reload, :queued?
    end

    # A client who picked someone gets that someone.
    test "a chosen review is not taken by anybody else" do
      result = Claim.call(review: reviews(:silent), profile: designer_profiles(:tom))

      assert_not_predicate result, :success?
      assert_predicate reviews(:silent).reload, :queued?
    end

    test "the chosen designer takes their own" do
      result = Claim.call(review: reviews(:silent), profile: designer_profiles(:ines))

      assert_predicate result, :success?
      assert_predicate reviews(:silent).reload, :in_progress?
    end

    test "the client is told when someone takes it" do
      assert_emails 1 do
        Claim.call(review: reviews(:queued), profile: designer_profiles(:ines))
        perform_enqueued_jobs
      end
    end
  end
end
