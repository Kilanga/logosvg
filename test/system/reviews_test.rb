require "application_system_test_case"

class ReviewsTest < ApplicationSystemTestCase
  setup do
    [ designs(:fox_screen), designs(:fox_dtf) ].each do |design|
      design.print_file.attach(
        io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
      )
    end
  end

  # The step's whole arc, from a designer taking the work to the client
  # accepting it.
  test "a designer takes a review, delivers it, and the client accepts" do
    sign_in users(:designer)
    click_on I18n.t("nav.review_queue")

    # Two are takeable by Inès: the open one and the one she was picked for.
    assert_text displayed("designer.reviews.index.available", count: 2)

    card = first("a[href='#{designer_review_path(reviews(:queued))}']").ancestor("li")

    within(card) { click_on I18n.t("designer.reviews.row.claim") }

    assert_text displayed("designer.reviews.claim.claimed")
    assert_predicate reviews(:queued).reload, :in_progress?

    # Delivering. The screen says which format the workshop expects.
    assert_text displayed("designer.reviews.show.deliver_hint.vector")

    attach_file "file", svg_path
    fill_in "version_message", with: "Tracés nettoyés, trois encres tenues."
    click_on I18n.t("designer.reviews.show.send_version")

    assert_text displayed("reviews.version", number: 1)
    assert_predicate reviews(:queued).reload, :delivered?

    # --- The client's side ---------------------------------------------------
    sign_out
    sign_in users(:client)
    visit review_path(reviews(:queued))

    assert_text displayed("client.reviews.show.your_turn")
    assert_text shown("Tracés nettoyés")

    click_on I18n.t("client.reviews.show.accept")

    assert_text displayed("enums.review.status.accepted")
    assert_predicate reviews(:queued).reload, :accepted?
  end

  # What was paid for is what is included.
  test "a client asks for a retour, and the count goes down" do
    sign_in users(:client)
    visit review_path(reviews(:delivered))

    assert_text displayed("client.reviews.show.revisions_left", count: 1)

    fill_in "revision_body", with: "Le contour du museau reste flou."
    click_on I18n.t("client.reviews.show.request_revision")

    assert_text displayed("client.reviews.revision.requested")
    assert_predicate reviews(:delivered).reload, :in_progress?
    assert_equal 1, reviews(:delivered).revisions_used
  end

  # Three of the five reasons carry no proposal, and the form says so.
  test "a designer hands a job back and the proposal fields follow the reason" do
    sign_in users(:designer)
    visit designer_review_path(reviews(:in_progress))

    choose "reason_unusable_design"

    assert_no_selector "[data-review-return-target='proposal']", visible: true

    choose "reason_level_too_low"

    assert_selector "[data-review-return-target='proposal']", visible: true

    select review_levels(:retouch).name, from: "proposed_level_id"
    fill_in "return_message", with: "Un simple contrôle ne suffira pas ici."
    accept_confirm { click_on I18n.t("designer.reviews.show.return_action") }

    assert_text displayed("designer.reviews.return_to_client.returned")
    assert_predicate reviews(:in_progress).reload, :returned_to_client?
  end

  test "the client reads the proposal and the difference in price" do
    sign_in users(:client)
    visit review_path(reviews(:returned))

    assert_text displayed("client.reviews.show.returned")
    assert_text shown(review_levels(:retouch).name)
    assert_text shown("+30,00 €")
    assert_button I18n.t("client.reviews.show.accept_and_pay")
  end

  # A cheaper level is applied at once: there is nothing to pay.
  test "a cheaper proposal is accepted without a payment screen" do
    reviews(:returned).update!(review_level: review_levels(:retouch), price_cents: 4900,
                               proposed_level: review_levels(:check))
    sign_in users(:client)
    visit review_path(reviews(:returned))

    assert_text shown("−30,00 €")
    click_on I18n.t("client.reviews.show.accept_and_refund")

    assert_text displayed("client.reviews.accept_proposal.accepted")
    assert_predicate reviews(:returned).reload, :queued?
  end

  # A designer who cannot be paid is never offered work to take.
  test "a designer Stripe cannot pay is told why instead of shown a queue" do
    sign_in users(:designer_unpaid)
    click_on I18n.t("nav.review_queue")

    assert_text displayed("designers.unavailable.payouts_disabled")
    assert_no_button I18n.t("designer.reviews.row.claim")
  end

  test "the two sides talk on the review" do
    sign_in users(:client)
    visit review_path(reviews(:in_progress))

    fill_in "message_body", with: "Est-ce que le fond peut rester transparent ?"
    click_on I18n.t("reviews.send")

    assert_text shown("Est-ce que le fond peut rester transparent")

    sign_out
    sign_in users(:designer)
    visit designer_review_path(reviews(:in_progress))

    assert_text shown("Est-ce que le fond peut rester transparent")
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

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end

    # Written outside the repository on purpose: the project path contains a
    # space ("logo svg"), and Selenium's file upload does not survive it.
    def svg_path
      @svg_path ||= begin
        file = Tempfile.new([ "version", ".svg" ], Dir.tmpdir)
        file.write(svg)
        file.close
        file.path
      end
    end
end
