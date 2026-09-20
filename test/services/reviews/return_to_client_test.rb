require "test_helper"

module Reviews
  # Two of the five reasons carry a proposal and the review waits; the other
  # three end it there and then, refunded.
  class ReturnToClientTest < ActiveSupport::TestCase
    test "a level that is too low comes back with a proposal and a deadline" do
      result = call(reason: "level_too_low", proposed_level: review_levels(:retouch))

      assert_predicate result, :success?

      review = reviews(:in_progress).reload

      assert_predicate review, :returned_to_client?
      assert_equal review_levels(:retouch), review.proposed_level
      assert_predicate review, :proposal_open?
      assert_in_delta 72.hours.from_now, review.proposal_expires_at, 1.minute
    end

    test "a level that is too high proposes the cheaper one" do
      review = reviews(:in_progress)
      review.update!(review_level: review_levels(:retouch), price_cents: 4900)

      call(reason: "level_too_high", proposed_level: review_levels(:check))

      assert_equal(-3000, review.reload.proposal_difference_cents)
    end

    # A custom job is quoted, so the designer names the price.
    test "a custom proposal carries the price the designer named" do
      call(reason: "level_too_low", proposed_level: review_levels(:custom),
           proposed_price_cents: 12_000)

      assert_equal 12_000, reviews(:in_progress).reload.proposed_amount_cents
    end

    test "a proposal with neither level nor price is refused" do
      result = call(reason: "level_too_low", proposed_level: nil)

      assert_not_predicate result, :success?
      assert_predicate reviews(:in_progress).reload, :in_progress?
    end

    # No level would make an unusable design usable, so there is nothing to
    # propose and nothing to wait for.
    test "an unusable design ends the review and refunds it at once" do
      result = call(reason: "unusable_design")

      assert_predicate result, :success?
      assert_predicate reviews(:in_progress).reload, :canceled?
    end

    test "forbidden content ends it the same way" do
      call(reason: "forbidden_content")

      assert_predicate reviews(:in_progress).reload, :canceled?
    end

    test "a reason nobody offers is refused" do
      result = call(reason: "je_ne_veux_pas")

      assert_not_predicate result, :success?
      assert_predicate reviews(:in_progress).reload, :in_progress?
    end

    test "a message is always required" do
      result = call(reason: "unusable_design", message: "  ")

      assert_not_predicate result, :success?
      assert_equal I18n.t("reviews.errors.message_required"), result.error
    end

    # Once per review, and never after a version has changed hands.
    test "a review already returned cannot be returned again" do
      reviews(:in_progress).update!(returned_at: 1.day.ago)

      result = call(reason: "unusable_design")

      assert_not_predicate result, :success?
      assert_equal I18n.t("reviews.errors.already_returned"), result.error
    end

    test "a review with a version delivered cannot be returned" do
      review = reviews(:in_progress_vector)
      review.versions.create!(message: "v1", file: uploaded_svg)

      result = ReturnToClient.call(review: review, reason: "unusable_design",
                                   message: "Trop tard, mais quand même.")

      assert_not_predicate result, :success?
    end

    test "the client is told either way" do
      assert_emails 1 do
        call(reason: "level_too_low", proposed_level: review_levels(:retouch))
        perform_enqueued_jobs
      end
    end

    private
      def call(reason:, message: "Il faut redessiner les contours.", **rest)
        ReturnToClient.call(review: reviews(:in_progress), reason: reason, message: message, **rest)
      end

      def uploaded_svg
        Rack::Test::UploadedFile.new(
          StringIO.new(%(<svg xmlns="http://www.w3.org/2000/svg"><path d="M0 0h1v1H0z" fill="#000"/></svg>)),
          "image/svg+xml", original_filename: "v.svg"
        )
      end
  end
end
