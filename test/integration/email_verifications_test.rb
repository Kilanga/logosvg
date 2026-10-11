require "test_helper"

# The address of a new account is verified before it generates, sends, pays or
# subscribes (decided on 11/10/2026). The account signs in meanwhile, and sees
# why it is held.
class EmailVerificationsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @client = users(:client)
    @client.update!(email_verified_at: nil)
  end

  # --- The email and its link -----------------------------------------------------

  test "the email carries a link to the confirmation page" do
    email = AccountMailer.verify_email(@client)

    assert_equal [ @client.email_address ], email.to
    assert_equal "Confirmez votre adresse email", email.subject
    assert_match %r{/verifier-email/[^"\s]+}, email.text_part.body.to_s
  end

  test "opening the link only shows a page; its button verifies" do
    token = @client.generate_token_for(:email_verification)

    get email_verification_path(token)
    assert_response :success
    assert_match @client.email_address, response.body
    assert_not @client.reload.email_verified?

    patch email_verification_path(token)
    assert_redirected_to new_session_path
    assert @client.reload.email_verified?
  end

  test "signed in, confirming leads back to the space" do
    sign_in_as @client
    token = @client.generate_token_for(:email_verification)

    patch email_verification_path(token)

    assert_redirected_to client_dashboard_path
    follow_redirect!
    assert_match "Votre adresse est confirmée", response.body
  end

  test "a link serves once" do
    token = @client.generate_token_for(:email_verification)
    patch email_verification_path(token)

    get email_verification_path(token)

    assert_redirected_to new_session_path
    assert_equal I18n.t("email_verifications.show.invalid_link").squish, flash[:alert].squish
  end

  test "a link expires after three days" do
    token = @client.generate_token_for(:email_verification)

    travel User::EMAIL_VERIFICATION_PERIOD + 1.minute do
      patch email_verification_path(token)
    end

    assert_not @client.reload.email_verified?
  end

  test "a forged link verifies nothing" do
    patch email_verification_path("pas-un-jeton")

    assert_redirected_to new_session_path
    assert_not @client.reload.email_verified?
  end

  # --- Asking for another email -----------------------------------------------------

  # The limit of three in ten minutes is Rails' rate_limit, on a cache that is a null
  # store under test, as for sign-in and sign-up.
  test "the banner offers another email" do
    sign_in_as @client

    get client_dashboard_path
    assert_select "form[action=?]", email_verifications_path

    assert_enqueued_email_with AccountMailer, :verify_email, args: [ @client ] do
      post email_verifications_path
    end
    assert_redirected_to client_dashboard_path
  end

  test "a verified account sees no banner and is sent nothing" do
    @client.update!(email_verified_at: Time.current)
    sign_in_as @client

    get client_dashboard_path
    assert_select "form[action=?]", email_verifications_path, count: 0

    assert_no_enqueued_emails do
      post email_verifications_path
    end
  end

  # --- What waits for the address -------------------------------------------------

  test "an unverified client creates nothing" do
    sign_in_as @client

    get new_design_path
    assert_redirected_to client_dashboard_path
    get new_design_upload_path
    assert_redirected_to client_dashboard_path

    assert_no_difference "Design.count" do
      post designs_path, params: { design: { prompt: "un renard", technique: "screen_printing", style: "illustration" } }
    end

    assert_redirected_to client_dashboard_path
    assert_equal I18n.t("email_verifications.required").squish, flash[:alert].squish
  end

  test "an unverified client sends nothing to a workshop" do
    sign_in_as @client

    get new_design_print_request_path(designs(:fox_screen))
    assert_redirected_to client_dashboard_path

    assert_no_difference "PrintRequest.count" do
      post design_print_requests_path(designs(:fox_screen), atelier: printers(:rennes).slug),
           params: { print_request: { quantity: 10 } }
    end
  end

  test "an unverified workshop neither subscribes nor submits its page" do
    users(:printer).update!(email_verified_at: nil)
    sign_in_as users(:printer)

    post workshop_subscription_path, params: { plan: "listing" }
    assert_redirected_to workshop_dashboard_path

    post submit_workshop_profile_path
    assert_redirected_to workshop_dashboard_path
  end

  test "an unverified designer takes no review" do
    users(:designer).update!(email_verified_at: nil)
    sign_in_as users(:designer)

    post claim_designer_review_path(reviews(:queued))

    assert_predicate reviews(:queued).reload, :queued?
  end

  test "a request reaches the workshop once the address is verified" do
    stranger = User.create!(email_address: "inconnu@example.invalid", password: "motdepasse-test",
                            first_name: "Paul", last_name: "Inconnu", role: "client",
                            terms_accepted_at: Time.current)
    affiliation = ClientAffiliation.request!(client: stranger, printer: printers(:rennes))

    sign_in_as users(:printer)
    get workshop_clients_path
    assert_select "li", text: /Paul Inconnu/, count: 0

    token = stranger.generate_token_for(:email_verification)
    assert_enqueued_email_with AffiliationMailer, :requested, args: [ affiliation ] do
      patch email_verification_path(token)
    end

    get workshop_clients_path
    assert_select "li", text: /Paul Inconnu/
  end
end
