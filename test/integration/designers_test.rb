require "test_helper"

class DesignersTest < ActionDispatch::IntegrationTest
  # --- The public list ------------------------------------------------------

  test "the list shows active profiles and nothing else" do
    get designers_path

    assert_response :success
    assert_select "a[href=?]", designer_path(designer_profiles(:ines))
    assert_select "a[href=?]", designer_path(designer_profiles(:nour)), count: 0
    assert_select "a[href=?]", designer_path(designer_profiles(:suspendu)), count: 0
  end

  test "a profile awaiting review is not readable by a visitor" do
    get designer_path(designer_profiles(:nour))

    assert_response :redirect
  end

  test "but its owner previews it" do
    sign_in_as users(:designer_pending)

    get designer_path(designer_profiles(:nour))

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(I18n.t('public.designers.show.preview_only'))}/i
  end

  test "the specialty filter narrows the list" do
    get designers_path(specialite: "lettering")

    assert_select "a[href=?]", designer_path(designer_profiles(:tom))
    assert_select "a[href=?]", designer_path(designer_profiles(:ines)), count: 0
  end

  test "the level filter shows only the designers who take it" do
    get designers_path(niveau: review_levels(:custom).id)

    assert_select "a[href=?]", designer_path(designer_profiles(:ines))
    assert_select "a[href=?]", designer_path(designer_profiles(:tom)), count: 0
  end

  # The filter that matters most: a designer who cannot be paid cannot work.
  test "the available filter hides everyone who could not take the job" do
    get designers_path(disponibles: "1")

    assert_select "a[href=?]", designer_path(designer_profiles(:ines))
    assert_select "a[href=?]", designer_path(designer_profiles(:tom)), count: 0
    assert_select "a[href=?]", designer_path(designer_profiles(:leo)), count: 0
  end

  # Shown on the list either way, so a client can see who exists — but the
  # state is never hidden.
  test "a designer who cannot take work says so on the list" do
    get designers_path

    assert_select "body", text: /#{Regexp.escape(I18n.t('designers.unavailable.not_accepting'))}/i
  end

  # --- The designer's own profile -------------------------------------------

  test "a designer with no profile still gets a form" do
    sign_in_as users(:designer_blank)

    get edit_designer_profile_path

    assert_response :success
  end

  test "a designer fills in their profile and it waits for review" do
    sign_in_as users(:designer_blank)

    assert_difference "DesignerProfile.count", 1 do
      patch designer_profile_path, params: { designer_profile: {
        display_name: "Sasha Morel", city: "Brest",
        bio: "Illustration et lettrage pour le textile, depuis huit ans.",
        specialties: [ "lettering" ], languages: [ "fr" ],
        review_level_ids: [ review_levels(:check).id.to_s ]
      } }
    end

    profile = users(:designer_blank).reload.designer_profile

    assert_redirected_to edit_designer_profile_path
    assert_predicate profile, :pending_review?
    assert_equal [ review_levels(:check) ], profile.review_levels
  end

  # Publication is never the designer's own decision.
  test "a designer cannot publish themselves" do
    sign_in_as users(:designer_pending)

    patch designer_profile_path, params: { designer_profile: { display_name: "Nour", status: "active" } }

    assert_predicate designer_profiles(:nour).reload, :pending_review?
  end

  test "unchecking every level clears the set rather than being ignored" do
    sign_in_as users(:designer)

    patch designer_profile_path, params: { designer_profile: {
      display_name: "Inès Nadeau", review_level_ids: [ "" ]
    } }

    assert_empty designer_profiles(:ines).reload.review_levels
  end

  # A designer editing only their bio must not silently lose their levels.
  test "an edit that says nothing about levels leaves them alone" do
    sign_in_as users(:designer)

    patch designer_profile_path, params: { designer_profile: { city: "Grenoble" } }

    assert_equal 3, designer_profiles(:ines).reload.review_levels.size
  end

  test "a designer never reaches another designer's profile form" do
    sign_in_as users(:designer_away)

    patch designer_profile_path, params: { designer_profile: { display_name: "Renommé" } }

    assert_equal "Inès Nadeau", designer_profiles(:ines).reload.display_name
  end

  test "only a designer reaches the studio" do
    [ :client, :printer, :admin ].each do |role|
      sign_in_as users(role)
      get edit_designer_profile_path

      assert_response :redirect, "#{role} must not reach it"

      sign_out
    end
  end

  # --- Payouts --------------------------------------------------------------

  test "a designer sees where their payouts stand" do
    sign_in_as users(:designer)

    get designer_payouts_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(I18n.t('designer.payouts.show.enabled'))}/i
  end

  test "a designer who cannot be paid is offered the onboarding" do
    sign_in_as users(:designer_unpaid)

    get designer_payouts_path

    assert_select "form[action=?]", designer_payouts_onboarding_path
  end

  # Without keys there is nothing to redirect to, and saying so beats a 500.
  test "onboarding without Stripe configured says so rather than failing" do
    sign_in_as users(:designer_unpaid)

    post designer_payouts_onboarding_path

    assert_redirected_to designer_payouts_path
    assert_equal I18n.t("designers.errors.not_configured"), flash[:alert]
  end

  test "the Stripe dashboard needs an account to open" do
    sign_in_as users(:designer_unpaid)

    post designer_payouts_dashboard_path

    assert_redirected_to designer_payouts_path
  end

  # --- The administration ---------------------------------------------------

  test "an administrator sees the profiles waiting for a decision" do
    sign_in_as users(:admin)

    get admin_designers_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(designer_profiles(:nour).display_name)}/
  end

  test "an administrator publishes a complete profile, and the designer is told" do
    sign_in_as users(:admin)

    assert_emails 1 do
      patch admin_designer_path(designer_profiles(:nour)), params: { status: "active" }
      perform_enqueued_jobs
    end

    assert_predicate designer_profiles(:nour).reload, :active?
  end

  # An administrator cannot publish an empty page, however they got to the
  # button.
  test "an incomplete profile is not published" do
    designer_profiles(:nour).update!(bio: "")
    sign_in_as users(:admin)

    patch admin_designer_path(designer_profiles(:nour)), params: { status: "active" }

    assert_predicate designer_profiles(:nour).reload, :pending_review?
    assert_equal I18n.t("admin.designers.update.incomplete", name: "Nour Haddad"), flash[:alert]
  end

  test "an administrator suspends a published profile" do
    sign_in_as users(:admin)

    patch admin_designer_path(designer_profiles(:ines)), params: { status: "suspended" }

    assert_predicate designer_profiles(:ines).reload, :suspended?
  end

  test "only an administrator decides" do
    [ :client, :printer, :designer ].each do |role|
      sign_in_as users(role)
      patch admin_designer_path(designer_profiles(:nour)), params: { status: "active" }

      assert_predicate designer_profiles(:nour).reload, :pending_review?, "#{role} must not publish"

      sign_out
    end
  end

  # --- The webhook that decides who can be paid -----------------------------

  test "an account webhook is what turns payouts on" do
    ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test_placeholder_not_real"

    Payments::HandleWebhook.call(event: {
      id: "evt_acct_1", type: "account.updated",
      data: { object: { id: "acct_test_ines", payouts_enabled: false } }
    })

    assert_not_predicate designer_profiles(:ines).reload, :payouts_enabled?
  ensure
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end

  test "an account we do not know is ignored quietly" do
    assert_nothing_raised do
      Payments::HandleWebhook.call(event: {
        id: "evt_acct_2", type: "account.updated",
        data: { object: { id: "acct_someone_else", payouts_enabled: true } }
      })
    end
  end
end
