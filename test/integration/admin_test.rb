require "test_helper"

class AdminTest < ActionDispatch::IntegrationTest
  setup { BlockedTerm.reset_cache! }

  # --- Who gets in ----------------------------------------------------------

  test "every administration screen is closed to the other roles" do
    paths = [ admin_dashboard_path, admin_printers_path, admin_designers_path,
              admin_reviews_path, admin_levels_path, admin_blocked_terms_path,
              admin_status_path ]

    [ :client, :printer, :designer ].each do |role|
      sign_in_as users(role)

      paths.each do |path|
        get path

        assert_response :redirect, "#{role} must not reach #{path}"
      end

      sign_out
    end
  end

  # --- The dashboard --------------------------------------------------------

  test "the dashboard counts what is waiting on an administrator" do
    sign_in_as users(:admin)

    get admin_dashboard_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(I18n.t('admin.dashboards.show.waiting_on_you'))}/i
  end

  # --- Settling a dispute, end to end ---------------------------------------
  #
  # The completion criterion of step 9.

  test "an administrator settles a dispute: the review closes and the money moves" do
    ENV["STRIPE_SECRET_KEY"] = "sk_test_not_a_real_key_placeholder"
    stub_request(:post, %r{/v1/refunds}).to_return(
      headers: { "Content-Type" => "application/json" }, body: { id: "re_1" }.to_json
    )
    sign_in_as users(:admin)

    assert_emails 1 do
      post settle_admin_review_path(reviews(:in_progress)),
           params: { refund: "25", note: "Le graphiste n'a pas répondu ; remboursement partiel." }
      perform_enqueued_jobs
    end

    review = reviews(:in_progress).reload

    assert_predicate review, :canceled?
    assert_equal 2500, review.refunded_cents
    assert_equal users(:admin), review.settled_by
    assert_not_nil review.settled_at
    assert_match(/remboursement partiel/, review.admin_note)
  ensure
    ENV.delete("STRIPE_SECRET_KEY")
  end

  # A decision nobody can account for later is not a decision.
  test "a settlement without a note is refused" do
    sign_in_as users(:admin)

    post settle_admin_review_path(reviews(:in_progress)), params: { refund: "0", note: "  " }

    assert_predicate reviews(:in_progress).reload, :in_progress?
  end

  test "a refund beyond what is left to give back is refused" do
    sign_in_as users(:admin)

    post settle_admin_review_path(reviews(:in_progress)),
         params: { refund: "999", note: "Trop." }

    assert_predicate reviews(:in_progress).reload, :in_progress?
  end

  # Closing with nothing refunded is a legitimate outcome.
  test "an administrator may close without refunding" do
    sign_in_as users(:admin)

    post settle_admin_review_path(reviews(:in_progress)),
         params: { refund: "0", note: "Travail livré hors plateforme, réglé entre les parties." }

    review = reviews(:in_progress).reload

    assert_predicate review, :canceled?
    assert_equal 0, review.refunded_cents
  end

  test "a review already settled cannot be settled again" do
    reviews(:in_progress).cancel!
    reviews(:in_progress).save!
    sign_in_as users(:admin)

    post settle_admin_review_path(reviews(:in_progress)),
         params: { refund: "0", note: "Encore." }

    assert_nil reviews(:in_progress).reload.settled_at
  end

  test "nobody but an administrator settles" do
    [ :client, :designer ].each do |role|
      sign_in_as users(role)

      post settle_admin_review_path(reviews(:in_progress)), params: { refund: "0", note: "Moi." }

      assert_predicate reviews(:in_progress).reload, :in_progress?, "#{role} must not settle"

      sign_out
    end
  end

  test "the disputes filter shows work that has run past its deadline" do
    reviews(:in_progress).update!(due_at: 2.days.ago)
    sign_in_as users(:admin)

    get admin_reviews_path(filtre: "disputed")

    assert_select "a[href=?]", admin_review_path(reviews(:in_progress))
  end

  # --- Blocked terms --------------------------------------------------------

  test "an administrator adds a term, and it takes effect at once" do
    sign_in_as users(:admin)

    post admin_blocked_terms_path, params: { blocked_term: { term: "Adidas", reason: "Marque" } }

    assert_redirected_to admin_blocked_terms_path
    assert_equal "adidas", BlockedTerm.matching("un ballon adidas")
  end

  test "a client's prompt carrying a blocked term is refused without costing an attempt" do
    sign_in_as users(:client)

    assert_no_difference "Design.count" do
      post designs_path, params: { design: {
        prompt: "un logo nikee sur fond noir", style: "logo",
        technique: "screen_printing", colors_requested: 2, print_width_cm: 25
      } }
    end

    assert_response :unprocessable_entity
    assert_equal 0, GenerationQuota.for(users(:client)).used
  end

  test "deactivating a term lets the prompt through again" do
    sign_in_as users(:admin)

    patch admin_blocked_term_path(blocked_terms(:marque))

    assert_not_predicate blocked_terms(:marque).reload, :active?
    assert_nil BlockedTerm.matching("un logo nikee")
  end

  test "only an administrator edits the list" do
    sign_in_as users(:client)

    post admin_blocked_terms_path, params: { blocked_term: { term: "quelconque" } }

    assert_nil BlockedTerm.find_by(term: "quelconque")
  end

  # --- Review levels --------------------------------------------------------

  test "an administrator changes a level's price" do
    sign_in_as users(:admin)

    patch admin_level_path(review_levels(:check)), params: { review_level: {
      name: "Contrôle", price: "29", turnaround_hours: 24, revisions_included: 1, active: "1"
    } }

    assert_equal 2900, review_levels(:check).reload.price_cents
  end

  # This is what makes the screen safe to use.
  test "changing a level does not rewrite a review already bought" do
    before = reviews(:queued).price_cents
    sign_in_as users(:admin)

    patch admin_level_path(review_levels(:check)), params: { review_level: {
      name: "Contrôle", price: "99", turnaround_hours: 24, revisions_included: 1, active: "1"
    } }

    assert_equal before, reviews(:queued).reload.price_cents
  end

  test "a level taken out of circulation is no longer offered" do
    sign_in_as users(:admin)

    patch admin_level_path(review_levels(:custom)), params: { review_level: {
      name: "Création sur mesure", turnaround_hours: 96, revisions_included: 3, active: "0"
    } }

    assert_not_includes ReviewLevel.offered, review_levels(:custom).reload
  end

  # --- Service status -------------------------------------------------------

  test "the status page answers even when nothing is configured" do
    sign_in_as users(:admin)

    get admin_status_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(I18n.t('admin.status.show.check.generator'))}/i
  end

  test "an unreachable generator is reported rather than raising" do
    ENV["GENERATOR_URL"] = "http://generator.test"
    stub_request(:get, "http://generator.test/health").to_timeout
    sign_in_as users(:admin)

    get admin_status_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(I18n.t('admin.status.show.state.down'))}/i
  ensure
    ENV.delete("GENERATOR_URL")
  end

  test "a healthy generator is reported as in service" do
    ENV["GENERATOR_URL"] = "http://generator.test"
    stub_request(:get, "http://generator.test/health").to_return(
      headers: { "Content-Type" => "application/json" }, body: { status: "ok" }.to_json
    )
    sign_in_as users(:admin)

    get admin_status_path

    assert_select "body", text: /#{Regexp.escape(I18n.t('admin.status.show.state.ok'))}/i
  ensure
    ENV.delete("GENERATOR_URL")
  end
end
