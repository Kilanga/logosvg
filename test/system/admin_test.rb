require "application_system_test_case"

class AdminTest < ApplicationSystemTestCase
  setup { BlockedTerm.reset_cache! }

  # The completion criterion of step 9: a dispute handled end to end.
  test "an administrator finds a dispute, reads it, and settles it" do
    reviews(:in_progress).update!(due_at: 2.days.ago)
    ENV["STRIPE_SECRET_KEY"] = "sk_test_not_a_real_key_placeholder"
    stub_request(:post, %r{/v1/refunds}).to_return(
      headers: { "Content-Type" => "application/json" }, body: { id: "re_1" }.to_json
    )

    sign_in users(:admin)

    assert_text displayed("admin.dashboards.show.waiting_on_you")

    click_on I18n.t("nav.reviews")
    click_on I18n.t("admin.reviews.index.filter.disputed"), match: :first

    find("a[href='#{admin_review_path(reviews(:in_progress))}']").click

    # Both sides, the money, and the deadline that ran out — on one page.
    assert_text displayed("admin.reviews.show.money")
    assert_text shown(users(:client).full_name)
    assert_text shown(designer_profiles(:ines).display_name)

    fill_in "refund", with: "25"
    fill_in "note", with: "Le graphiste n'a pas tenu son échéance. Remboursement partiel."
    accept_confirm { click_on I18n.t("admin.reviews.show.settle_action") }

    assert_text displayed("admin.reviews.settle.settled")

    review = reviews(:in_progress).reload

    assert_predicate review, :canceled?
    assert_equal 2500, review.refunded_cents
    assert_equal users(:admin), review.settled_by
  ensure
    ENV.delete("STRIPE_SECRET_KEY")
  end

  # A decision nobody can account for later is not a decision.
  test "a settlement without a written decision is refused" do
    sign_in users(:admin)
    visit admin_review_path(reviews(:in_progress))

    fill_in "refund", with: "0"
    # No `accept_confirm`: the note is a required field, so the browser stops
    # the submission before Turbo ever asks for confirmation.
    click_on I18n.t("admin.reviews.show.settle_action")

    assert_selector "textarea#note:invalid"
    assert_predicate reviews(:in_progress).reload, :in_progress?
  end

  test "an administrator blocks a term and a client is turned away by it" do
    sign_in users(:admin)
    click_on I18n.t("nav.blocked_terms")

    fill_in "blocked_term_term", with: "Adidas"
    fill_in "blocked_term_reason", with: "Marque déposée"
    click_on I18n.t("admin.blocked_terms.index.add_action")

    assert_text shown("adidas")

    sign_out
    sign_in users(:client)
    visit new_design_path

    choose "design_technique_screen_printing", allow_label_click: true
    fill_in "design_prompt", with: "un ballon adidas sur fond blanc"
    click_on I18n.t("client.designs.new.submit")

    assert_text shown("adidas")
    assert_equal 0, GenerationQuota.for(users(:client)).used, "a refusal costs no attempt"
  end

  test "an administrator changes a level's price without touching what was sold" do
    before = reviews(:queued).price_cents

    sign_in users(:admin)
    click_on I18n.t("nav.levels")

    assert_text displayed("admin.review_levels.index.safe_title")

    within("section", text: shown(review_levels(:check).name)) do
      fill_in "review_level_price_#{review_levels(:check).id}", with: "29"
      click_on I18n.t("admin.review_levels.index.save")
    end

    assert_text displayed("admin.review_levels.update.saved", name: "Contrôle")
    assert_equal 2900, review_levels(:check).reload.price_cents
    assert_equal before, reviews(:queued).reload.price_cents
  end

  test "the status page says what is up and what is not" do
    sign_in users(:admin)
    click_on I18n.t("nav.status")

    assert_selector "h1", text: displayed("admin.status.show.heading")
    assert_text displayed("admin.status.show.check.generator")
    assert_text displayed("admin.status.show.check.queue")
  end

  private
    def sign_in(user)
      visit new_session_path
      fill_in I18n.t("activerecord.attributes.user.email_address"), with: user.email_address
      fill_in I18n.t("activerecord.attributes.user.password"), with: "motdepasse-test"
      click_on I18n.t("sessions.new.submit")

      assert_no_current_path new_session_path
    end

    def sign_out
      click_on I18n.t("nav.sign_out")
      assert_text displayed("nav.sign_in")
    end
end
