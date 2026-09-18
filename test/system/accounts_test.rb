require "application_system_test_case"

class AccountsTest < ApplicationSystemTestCase
  test "a print shop signs up from the home page and lands in its workshop" do
    visit root_path
    click_on I18n.t("public.home.show.cta_primary")

    # The role announced by the link is the one already selected.
    assert_checked_field "user_role_printer", visible: false

    fill_in I18n.t("activerecord.attributes.user.first_name"), with: "Bruno"
    fill_in I18n.t("activerecord.attributes.user.last_name"), with: "Leroy"
    fill_in I18n.t("activerecord.attributes.user.email_address"), with: "nouvel-atelier@example.invalid"
    fill_in I18n.t("activerecord.attributes.user.password"), with: "motdepasse-test"
    fill_in I18n.t("activerecord.attributes.user.password_confirmation"), with: "motdepasse-test"
    check I18n.t("registrations.new.terms")

    click_on I18n.t("registrations.new.submit")

    assert_current_path "/atelier"
    assert_selector "h1", text: displayed("workshop.dashboards.show.heading", name: "Bruno")
  end

  test "a client signs in, sees their space, and signs out" do
    visit root_path
    click_on I18n.t("nav.sign_in")

    fill_in I18n.t("activerecord.attributes.user.email_address"), with: users(:client).email_address
    fill_in I18n.t("activerecord.attributes.user.password"), with: "motdepasse-test"
    click_on I18n.t("sessions.new.submit")

    assert_current_path "/mon-espace"
    assert_text displayed("roles.client")

    click_on I18n.t("nav.sign_out")

    assert_current_path root_path
    assert_text displayed("nav.sign_in")
  end

  test "a designer who reaches for the workshop is sent back to the studio" do
    sign_in_through_form users(:designer)
    assert_current_path "/studio"

    visit "/atelier"

    assert_current_path "/studio"
    assert_text displayed("flash.unauthorized")
  end

  test "wrong credentials keep the visitor on the form, without saying why" do
    visit new_session_path

    fill_in I18n.t("activerecord.attributes.user.email_address"), with: users(:client).email_address
    fill_in I18n.t("activerecord.attributes.user.password"), with: "pas-le-bon"
    click_on I18n.t("sessions.new.submit")

    assert_current_path new_session_path
    assert_text displayed("sessions.create.failed")
  end

  private
    def sign_in_through_form(user)
      visit new_session_path
      fill_in I18n.t("activerecord.attributes.user.email_address"), with: user.email_address
      fill_in I18n.t("activerecord.attributes.user.password"), with: "motdepasse-test"
      click_on I18n.t("sessions.new.submit")
    end
end
