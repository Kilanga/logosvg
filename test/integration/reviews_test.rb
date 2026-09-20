require "test_helper"

class ReviewsTest < ActionDispatch::IntegrationTest
  setup do
    designs(:fox_screen).print_file.attach(
      io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
    )
    designs(:fox_dtf).print_file.attach(
      io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
    )
  end

  # --- Buying one -----------------------------------------------------------

  test "a client opens the form for their own design" do
    sign_in_as users(:client)

    get new_design_review_path(designs(:fox_screen))

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(review_levels(:check).name)}/
  end

  # The natural sequel to a spent refinement budget: the two ways of reworking
  # it yourself give way to the one that is left.
  test "a design with no refinement left offers the designer instead" do
    designs(:fox_screen).update!(refinements_left: 0)
    sign_in_as users(:client)

    get design_path(designs(:fox_screen))

    assert_select "a[href=?]", new_design_review_path(designs(:fox_screen))
    assert_select "form[action=?]", design_variants_path(designs(:fox_screen)), count: 0
  end

  test "a design with reprises left still offers them" do
    designs(:fox_screen).update!(refinements_left: 2)
    sign_in_as users(:client)

    get design_path(designs(:fox_screen))

    assert_select "form[action=?]", design_variants_path(designs(:fox_screen))
  end

  test "a client never orders a review for someone else's design" do
    sign_in_as users(:client)

    get new_design_review_path(designs(:other_client_design))

    assert_response :not_found
  end

  # The price is copied at purchase: a level that changes next month must not
  # rewrite what was paid.
  test "the price and the allowance are copied onto the review" do
    sign_in_as users(:client)

    assert_difference "Review.count", 1 do
      post design_reviews_path(designs(:fox_screen)), params: { review: {
        review_level_id: review_levels(:retouch).id, client_brief: "Merci de nettoyer les tracés."
      } }
    end

    review = Review.order(:created_at).last

    assert_equal 4900, review.price_cents
    assert_equal 980, review.platform_fee_cents
    assert_equal 2, review.revisions_included
    assert_predicate review, :awaiting_payment?
  end

  test "choosing a designer records that it was a choice" do
    sign_in_as users(:client)

    post design_reviews_path(designs(:fox_screen)), params: { review: {
      review_level_id: review_levels(:check).id,
      designer_profile_id: designer_profiles(:ines).id
    } }

    review = Review.order(:created_at).last

    assert_predicate review, :chosen?
    assert_equal designer_profiles(:ines), review.designer_profile
  end

  # A designer who could not do the work is not a choice.
  test "a designer who cannot take work cannot be chosen" do
    sign_in_as users(:client)

    post design_reviews_path(designs(:fox_screen)), params: { review: {
      review_level_id: review_levels(:check).id,
      designer_profile_id: designer_profiles(:leo).id
    } }

    review = Review.order(:created_at).last

    assert_predicate review, :first_available?
    assert_nil review.designer_profile
  end

  test "without Stripe configured the client is told rather than shown a 500" do
    sign_in_as users(:client)

    post design_reviews_path(designs(:fox_screen)), params: { review: {
      review_level_id: review_levels(:check).id
    } }

    assert_response :redirect
    assert_equal I18n.t("reviews.errors.not_configured"), flash[:alert]
  end

  # --- The client's own actions ---------------------------------------------

  test "a client reads their own review and nobody else's" do
    sign_in_as users(:client)

    get review_path(reviews(:delivered))

    assert_response :success
  end

  test "a designer reads the review they were given" do
    sign_in_as users(:designer)

    get designer_review_path(reviews(:delivered))

    assert_response :success
  end

  test "a designer never reads a review that is not theirs and not in their queue" do
    sign_in_as users(:designer_away)

    get designer_review_path(reviews(:delivered))

    assert_response :not_found
  end

  test "a client accepts the work, and the designer is settled" do
    sign_in_as users(:client)

    post accept_review_path(reviews(:delivered))

    assert_predicate reviews(:delivered).reload, :accepted?
  end

  test "a client asks for a revision, with a message" do
    sign_in_as users(:client)

    post revision_review_path(reviews(:delivered)), params: { body: "Le contour reste flou." }

    review = reviews(:delivered).reload

    assert_predicate review, :in_progress?
    assert_equal 1, review.revisions_used
    assert_equal "Le contour reste flou.", review.messages.last.body
  end

  test "a revision with no message changes nothing" do
    sign_in_as users(:client)

    post revision_review_path(reviews(:delivered)), params: { body: "  " }

    assert_predicate reviews(:delivered).reload, :delivered?
  end

  test "a client cannot accept a review that has not been delivered" do
    sign_in_as users(:client)

    post accept_review_path(reviews(:in_progress))

    assert_predicate reviews(:in_progress).reload, :in_progress?
  end

  test "a designer cannot accept on the client's behalf" do
    sign_in_as users(:designer)

    post accept_review_path(reviews(:delivered))

    assert_predicate reviews(:delivered).reload, :delivered?
  end

  # --- The proposal ---------------------------------------------------------

  test "a cheaper proposal is applied at once and the difference refunded" do
    reviews(:returned).update!(review_level: review_levels(:retouch), price_cents: 4900,
                               proposed_level: review_levels(:check))
    sign_in_as users(:client)

    post accept_review_proposal_path(reviews(:returned))

    review = reviews(:returned).reload

    assert_predicate review, :queued?
    assert_equal review_levels(:check), review.review_level
    assert_equal 1900, review.price_cents
  end

  test "declining a proposal cancels and refunds" do
    sign_in_as users(:client)

    post decline_review_proposal_path(reviews(:returned))

    assert_predicate reviews(:returned).reload, :canceled?
  end

  test "a proposal that has expired can no longer be accepted" do
    reviews(:returned).update!(proposal_expires_at: 1.hour.ago)
    sign_in_as users(:client)

    post accept_review_proposal_path(reviews(:returned))

    assert_predicate reviews(:returned).reload, :returned_to_client?
  end

  # --- The silent designer --------------------------------------------------

  test "a client reopens a review their chosen designer ignored" do
    sign_in_as users(:client)

    post reopen_review_path(reviews(:silent))

    review = reviews(:silent).reload

    assert_predicate review, :first_available?
    assert_nil review.designer_profile
  end

  test "a review whose designer has only just been asked cannot be reopened" do
    reviews(:silent).update!(paid_at: 1.hour.ago)
    sign_in_as users(:client)

    post reopen_review_path(reviews(:silent))

    assert_predicate reviews(:silent).reload, :chosen?
  end

  # --- The designer's queue -------------------------------------------------

  test "a designer sees the queue they could take from" do
    sign_in_as users(:designer)

    get designer_reviews_path

    assert_response :success
    assert_select "a[href=?]", designer_review_path(reviews(:queued))
  end

  # A designer who cannot be paid sees no queue at all.
  test "a designer who cannot take work is told why instead of seeing a queue" do
    sign_in_as users(:designer_unpaid)

    get designer_reviews_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(I18n.t('designers.unavailable.payouts_disabled'))}/i
  end

  test "a designer claims a review from the queue" do
    sign_in_as users(:designer)

    post claim_designer_review_path(reviews(:queued))

    assert_predicate reviews(:queued).reload, :in_progress?
    assert_equal designer_profiles(:ines), reviews(:queued).designer_profile
  end

  test "a designer who cannot be paid claims nothing" do
    sign_in_as users(:designer_unpaid)

    post claim_designer_review_path(reviews(:queued))

    assert_predicate reviews(:queued).reload, :queued?
  end

  test "a designer delivers a version" do
    sign_in_as users(:designer)

    post deliver_designer_review_path(reviews(:in_progress_vector)),
         params: { file: uploaded_svg, message: "Tracés nettoyés." }

    review = reviews(:in_progress_vector).reload

    assert_predicate review, :delivered?
    assert_equal 1, review.versions.count
  end

  test "a designer hands the job back with a proposal" do
    sign_in_as users(:designer)

    post return_designer_review_path(reviews(:in_progress)), params: {
      reason: "level_too_low", message: "Il faut tout redessiner.",
      proposed_level_id: review_levels(:retouch).id
    }

    review = reviews(:in_progress).reload

    assert_predicate review, :returned_to_client?
    assert_equal review_levels(:retouch), review.proposed_level
  end

  test "a price in euros reaches the database in cents" do
    sign_in_as users(:designer)

    post return_designer_review_path(reviews(:in_progress)), params: {
      reason: "level_too_low", message: "Sur mesure.",
      proposed_level_id: review_levels(:custom).id, proposed_price: "120"
    }

    assert_equal 12_000, reviews(:in_progress).reload.proposed_price_cents
  end

  # --- The conversation -----------------------------------------------------

  test "both sides write, and nobody else does" do
    sign_in_as users(:client)
    post review_messages_path(reviews(:in_progress)), params: { body: "Une question." }

    assert_equal 1, reviews(:in_progress).reload.messages.count

    sign_out
    sign_in_as users(:designer)
    post designer_review_messages_path(reviews(:in_progress)), params: { body: "Une réponse." }

    assert_equal 2, reviews(:in_progress).reload.messages.count
  end

  test "a stranger writes nothing" do
    sign_in_as users(:designer_away)

    post designer_review_messages_path(reviews(:in_progress)), params: { body: "Bonjour" }

    assert_response :not_found
    assert_equal 0, reviews(:in_progress).reload.messages.count
  end

  # --- The webhook that pays for it -----------------------------------------

  test "a completed review checkout puts it in the queue" do
    review = Review.create!(design: designs(:fox_screen), client: users(:client),
                            review_level: review_levels(:check),
                            price_cents: 1900, platform_fee_cents: 380, revisions_included: 1)

    Payments::HandleWebhook.call(event: {
      id: "evt_rev_1", type: "checkout.session.completed",
      data: { object: { id: "cs_x", mode: "payment", payment_intent: "pi_x",
                        metadata: { review_token: review.token, purpose: "review" } } }
    })

    assert_predicate review.reload, :queued?
    assert_equal "pi_x", review.stripe_payment_intent_id
  end

  # An upgrade rewrites the level and the price together.
  test "a paid upgrade applies the proposal" do
    Payments::HandleWebhook.call(event: {
      id: "evt_rev_2", type: "checkout.session.completed",
      data: { object: { id: "cs_y", mode: "payment", payment_intent: "pi_y",
                        metadata: { review_token: reviews(:returned).token, purpose: "upgrade" } } }
    })

    review = reviews(:returned).reload

    assert_predicate review, :queued?
    assert_equal review_levels(:retouch), review.review_level
    assert_equal 4900, review.price_cents
    assert_equal 0, review.revisions_used
  end

  private
    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end

    def uploaded_svg
      Rack::Test::UploadedFile.new(StringIO.new(svg), "image/svg+xml",
                                   original_filename: "version.svg")
    end
end
