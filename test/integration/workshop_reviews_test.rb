require "test_helper"

# Decided on 09/10/2026: the workshop a design was made for follows the
# designer's work on it, on screen and in copy of the site's emails; no client
# pays for a review no designer could take.
class WorkshopReviewsTest < ActionDispatch::IntegrationTest
  test "the shop sees the reviews on designs made for it, and only those" do
    sign_in_as users(:printer)

    get workshop_reviews_path

    assert_response :success
    rennes = Review.joins(:design).where(designs: { printer_id: printers(:rennes).id })
                   .where.not(status: "awaiting_payment")
    lyon = Review.joins(:design).where(designs: { printer_id: printers(:lyon).id })
    assert_select "main ul.divide-y > li", count: rennes.count
    assert lyon.any?, "the fixtures must hold a review for another shop"
  end

  test "the shop is copied on the emails about the work, not on the money" do
    review = reviews(:queued)
    shop = printers(:rennes).orders_email

    assert_equal [ shop ], ReviewMailer.designer_silent(review).cc
    assert_equal [ shop ], ReviewMailer.unclaimed(review).cc
    assert_nil ReviewMailer.refunded(review, 100).cc
  end

  test "a design made for no shop copies nobody" do
    review = reviews(:queued)
    review.design.update_column(:printer_id, nil)

    assert_nil ReviewMailer.designer_silent(review).cc
  end

  test "the client is told on the form that the shop follows the review" do
    sign_in_as users(:client)

    get new_design_review_path(designs(:fox_screen))

    assert_match "Sérigraphie du Thabor, l&#39;atelier pour lequel ce visuel a été créé", response.body
  end

  test "with no designer taking work, there is nothing to pay for" do
    DesignerProfile.update_all(accepting_work: false)
    sign_in_as users(:client)

    get new_design_review_path(designs(:fox_screen))
    assert_match "Aucun graphiste disponible pour le moment", response.body

    assert_no_difference "Review.count" do
      post design_reviews_path(designs(:fox_screen)),
           params: { review: { review_level_id: review_levels(:check).id, brief: { change: "le fond" } } }
    end
    assert_response :unprocessable_entity
  end

  # --- The shop's recommended designer --------------------------------------

  test "a shop recommends a designer, then withdraws the recommendation" do
    sign_in_as users(:printer)

    patch workshop_recommended_designer_path, params: { designer_profile_id: designer_profiles(:ines).id }
    assert_equal designer_profiles(:ines).id, printers(:rennes).reload.recommended_designer_profile_id

    patch workshop_recommended_designer_path, params: { designer_profile_id: "" }
    assert_nil printers(:rennes).reload.recommended_designer_profile_id
  end

  test "a suspended designer cannot be recommended" do
    sign_in_as users(:printer)

    patch workshop_recommended_designer_path, params: { designer_profile_id: designer_profiles(:suspendu).id }

    assert_nil printers(:rennes).reload.recommended_designer_profile_id
  end

  test "the client sees the shop's designer first, marked and selected" do
    recommended = DesignerProfile.listed.accepting.by_reputation.to_a.last
    printers(:rennes).update_column(:recommended_designer_profile_id, recommended.id)
    sign_in_as users(:client)

    get new_design_review_path(designs(:fox_screen))

    assert_select "input[name=?][value=?][checked]", "review[designer_profile_id]", recommended.id.to_s
    labels = css_select("input[name='review[designer_profile_id]']").map { |input| input["value"] }
    assert_equal [ "", recommended.id.to_s ], labels.first(2), "first after « premier disponible »"
    assert_match "Recommandé par votre atelier", response.body
  end

  test "a recommended designer not taking work is not pushed forward" do
    recommended = designer_profiles(:ines)
    recommended.update_column(:accepting_work, false)
    printers(:rennes).update_column(:recommended_designer_profile_id, recommended.id)
    sign_in_as users(:client)

    get new_design_review_path(designs(:fox_screen))

    assert_no_match "Recommandé par votre atelier", response.body
  end
end
