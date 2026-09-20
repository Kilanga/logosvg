require "application_system_test_case"

class DesignersTest < ApplicationSystemTestCase
  # The two gates a designer passes before anything can be given to them, and
  # the fact that neither alone is enough.
  test "a designer fills in their profile and waits on both gates" do
    sign_in users(:designer_blank)

    assert_text displayed("designer.dashboards.show.before_you_start")
    assert_text displayed("designer.dashboards.show.step.profile.title")

    click_on I18n.t("nav.my_profile")

    fill_in "designer_profile_display_name", with: "Sasha Morel"
    fill_in "designer_profile_bio", with: "Lettrage et illustration pour le textile, depuis huit ans."
    fill_in "designer_profile_city", with: "Brest"
    check "specialty_lettering"
    check "level_check"

    click_on I18n.t("designer.profiles.edit.save")

    assert_text displayed("designer.profiles.update.saved")
    assert_text displayed("enums.designer_profile.status.pending_review")

    profile = users(:designer_blank).reload.designer_profile

    assert_equal [ review_levels(:check) ], profile.review_levels
    assert_not_predicate profile, :can_take_work?, "neither gate is passed yet"

    # Payouts is the second gate, and the studio says so.
    visit designer_dashboard_path

    assert_text displayed("designer.dashboards.show.step.payouts.title")
    assert_text displayed("designers.unavailable.pending_review")
  end

  # The completion criterion, walked: payouts alone, and vetting alone, are
  # each not enough.
  test "neither gate alone lets a designer take work" do
    sign_in users(:designer_pending)

    assert_text displayed("designers.unavailable.pending_review")

    sign_out
    sign_in users(:designer_unpaid)

    assert_text displayed("designers.unavailable.payouts_disabled")
  end

  test "a designer who passed both gates is told they are ready" do
    sign_in users(:designer)

    assert_text displayed("designer.dashboards.show.ready")
  end

  test "the payouts screen says who holds the identity documents" do
    sign_in users(:designer_unpaid)
    click_on I18n.t("nav.payouts")

    assert_text displayed("designer.payouts.show.who_holds_what")
    assert_button I18n.t("designer.payouts.show.start")
  end

  # --- The public side ------------------------------------------------------

  test "a visitor browses the designers and opens one" do
    visit root_path
    visit designers_path

    assert_selector "h1", text: displayed("public.designers.index.title")
    assert_text shown(designer_profiles(:ines).display_name)
    assert_no_text shown(designer_profiles(:nour).display_name)

    find("a[href='#{designer_path(designer_profiles(:ines))}']", match: :first).click

    assert_selector "h1", text: shown(designer_profiles(:ines).display_name)
    assert_text shown(review_levels(:check).name)
    assert_text displayed("designers.levels.quoted"), exact: false
  end

  test "the available filter leaves only the designers who could take the job" do
    visit designers_path

    assert_text shown(designer_profiles(:tom).display_name)

    check I18n.t("public.designers.index.filters.available")
    click_on I18n.t("public.designers.index.filters.apply")

    assert_text shown(designer_profiles(:ines).display_name)
    assert_no_text shown(designer_profiles(:tom).display_name)
  end

  # --- The administration ---------------------------------------------------

  test "an administrator publishes a profile and it appears in the list" do
    sign_in users(:admin)
    click_on I18n.t("nav.designers")

    within("li", text: shown(designer_profiles(:nour).display_name)) do
      click_on I18n.t("admin.designers.row.activate")
    end

    assert_text displayed("admin.designers.update.active", name: "Nour Haddad")
    assert_predicate designer_profiles(:nour).reload, :active?

    sign_out
    visit designers_path

    assert_text shown(designer_profiles(:nour).display_name)
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
