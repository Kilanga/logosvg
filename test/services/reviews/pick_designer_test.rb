require "test_helper"

module Reviews
  class PickDesignerTest < ActiveSupport::TestCase
    test "a client picks a different designer, at the same level and price" do
      result = call(designer_profile_id: designer_profiles(:maya).id)

      assert_predicate result, :success?

      review = reviews(:returned).reload

      assert_predicate review, :queued?
      assert_equal designer_profiles(:maya), review.designer_profile
      assert_equal "chosen", review.assignment_mode
      assert_equal review_levels(:check), review.review_level
      assert_equal 1900, review.price_cents
    end

    test "the designer who already returned it cannot be picked again" do
      result = call(designer_profile_id: designer_profiles(:ines).id)

      assert_not_predicate result, :success?
      assert_equal I18n.t("reviews.errors.already_refused"), result.error
      assert_predicate reviews(:returned).reload, :returned_to_client?
    end

    test "a designer who does not accept this level is refused" do
      reviews(:returned).update!(review_level: review_levels(:custom))

      result = call(designer_profile_id: designer_profiles(:maya).id)

      assert_not_predicate result, :success?
      assert_equal I18n.t("reviews.errors.level_not_accepted"), result.error
    end

    test "an unlisted designer is refused" do
      result = call(designer_profile_id: designer_profiles(:nour).id)

      assert_not_predicate result, :success?
      assert_equal I18n.t("reviews.errors.designer_required"), result.error
    end

    test "once the cap is reached, no new designer can be picked" do
      reviews(:returned).update!(designer_refusals_count: Review::MAX_DESIGNER_REFUSALS)

      result = call(designer_profile_id: designer_profiles(:maya).id)

      assert_not_predicate result, :success?
      assert_equal I18n.t("reviews.errors.reassignment_closed"), result.error
    end

    test "the new designer is told" do
      assert_emails 1 do
        call(designer_profile_id: designer_profiles(:maya).id)
        perform_enqueued_jobs
      end
    end

    private
      def call(**attributes)
        PickDesigner.call(review: reviews(:returned), **attributes)
      end
  end
end
