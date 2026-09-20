require "test_helper"

# Every transition, including the ones that must not happen.
# See docs/SPEC.md, "Revue graphiste".
class ReviewStateMachineTest < ActiveSupport::TestCase
  test "a review starts awaiting payment" do
    assert_predicate Review.new, :awaiting_payment?
  end

  test "payment puts it in the queue, and stamps when" do
    review = build_review

    assert review.may_pay?
    review.pay!

    assert_predicate review, :queued?
    assert_not_nil review.paid_at
  end

  test "a designer who can take it claims it" do
    review = reviews(:queued)
    review.designer_profile = designer_profiles(:ines)

    assert review.may_claim?
    review.claim!

    assert_predicate review, :in_progress?
  end

  # The rule step 7 exists for, enforced where the work is handed over.
  test "a designer who cannot be paid cannot claim" do
    review = reviews(:queued)
    review.designer_profile = designer_profiles(:leo)

    assert_not review.may_claim?
    assert_raises(AASM::InvalidTransition) { review.claim! }
  end

  test "a designer who does not take this level cannot claim it" do
    review = reviews(:queued)
    review.designer_profile = designer_profiles(:tom)
    review.review_level = review_levels(:custom)

    assert_not review.claimable_by?(designer_profiles(:tom))
  end

  # A client who picked someone gets that someone.
  test "a chosen review is not claimable by another designer" do
    review = reviews(:silent)

    assert_not review.claimable_by?(designer_profiles(:tom))
    assert review.claimable_by?(designer_profiles(:ines))
  end

  test "delivering moves it to delivered and stamps when" do
    review = reviews(:in_progress)

    assert review.may_deliver?
    review.deliver!

    assert_predicate review, :delivered?
    assert_not_nil review.delivered_at
  end

  test "a revision goes back to the designer and is counted" do
    review = reviews(:delivered)

    assert review.may_request_revision?
    review.request_revision!

    assert_predicate review, :in_progress?
    assert_equal 1, review.revisions_used
  end

  # What was paid for is what is included; asking beyond it is not refused
  # rudely, it simply is not this transition.
  test "a revision beyond what was paid for is refused" do
    review = reviews(:delivered)
    review.update!(revisions_used: review.revisions_included)

    assert_not review.may_request_revision?
    assert_raises(AASM::InvalidTransition) { review.request_revision! }
  end

  test "accepting ends it and stamps when" do
    review = reviews(:delivered)

    assert review.may_accept?
    review.accept!

    assert_predicate review, :accepted?
    assert_not_nil review.accepted_at
  end

  test "a designer hands the job back before delivering anything" do
    review = reviews(:in_progress)

    assert review.may_return_to_client?
    review.return_to_client!

    assert_predicate review, :returned_to_client?
    assert_not_nil review.returned_at
  end

  test "a queued review can be handed back too, without being claimed" do
    assert reviews(:queued).may_return_to_client?
  end

  # Once per review, and never after a version has changed hands.
  test "a review already handed back once cannot be handed back again" do
    review = reviews(:in_progress)
    review.update!(returned_at: 1.day.ago)

    assert_not review.may_return_to_client?
  end

  test "a review with a version delivered can no longer be handed back" do
    review = reviews(:in_progress)
    review.versions.create!(message: "Première version", file: uploaded_svg)

    assert_not_predicate review, :returnable?
  end

  test "accepting a proposal puts it back in the queue" do
    review = reviews(:returned)

    assert review.may_accept_proposal?
    review.accept_proposal!

    assert_predicate review, :queued?
  end

  test "a proposal that has expired can no longer be accepted" do
    review = reviews(:returned)
    review.update!(proposal_expires_at: 1.hour.ago)

    assert_not review.may_accept_proposal?
    assert_raises(AASM::InvalidTransition) { review.accept_proposal! }
  end

  test "declining a proposal cancels the review" do
    review = reviews(:returned)

    assert review.may_decline_proposal?
    review.decline_proposal!

    assert_predicate review, :canceled?
    assert_not_nil review.canceled_at
  end

  test "an administrator cancels from any state that is still open" do
    %i[ queued in_progress delivered returned ].each do |fixture|
      review = reviews(fixture)

      assert review.may_cancel?, "#{fixture} should be cancellable"
      review.cancel!

      assert_predicate review, :canceled?
    end
  end

  # --- The transitions that must not happen --------------------------------

  test "an unpaid review cannot be claimed or delivered" do
    review = build_review

    assert_not review.may_claim?
    assert_not review.may_deliver?
    assert_raises(AASM::InvalidTransition) { review.claim! }
    assert_raises(AASM::InvalidTransition) { review.deliver! }
  end

  test "a queued review cannot be delivered before anyone takes it" do
    assert_not reviews(:queued).may_deliver?
    assert_raises(AASM::InvalidTransition) { reviews(:queued).deliver! }
  end

  test "a review in progress cannot be accepted before a version exists" do
    assert_not reviews(:in_progress).may_accept?
    assert_raises(AASM::InvalidTransition) { reviews(:in_progress).accept! }
  end

  test "a review cannot be paid twice" do
    assert_not reviews(:queued).may_pay?
    assert_raises(AASM::InvalidTransition) { reviews(:queued).pay! }
  end

  test "an accepted review never moves again" do
    review = reviews(:delivered).tap(&:accept!)

    assert_not review.may_cancel?
    assert_not review.may_request_revision?
    assert_not review.may_deliver?

    assert_raises(AASM::InvalidTransition) { review.cancel! }
    assert_raises(AASM::InvalidTransition) { review.request_revision! }
  end

  test "a canceled review never moves again" do
    review = reviews(:queued).tap(&:cancel!)

    assert_not review.may_claim?
    assert_not review.may_accept?
    assert_raises(AASM::InvalidTransition) { review.claim! }
    assert_raises(AASM::InvalidTransition) { review.accept! }
  end

  test "a returned review cannot be claimed until the client answers" do
    assert_not reviews(:returned).may_claim?
    assert_raises(AASM::InvalidTransition) { reviews(:returned).claim! }
  end

  private
    def build_review(**attributes)
      Review.create!({
        design: designs(:fox_screen),
        client: users(:client),
        review_level: review_levels(:check),
        price_cents: 1900,
        platform_fee_cents: 380,
        revisions_included: 1
      }.merge(attributes))
    end

    def uploaded_svg
      Rack::Test::UploadedFile.new(
        StringIO.new(%(<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0h1v1H0z" fill="#000"/></svg>)),
        "image/svg+xml", original_filename: "version.svg"
      )
    end
end
