require "application_system_test_case"

class PrintersTest < ApplicationSystemTestCase
  # Below the breakpoint that reveals the map, so no OpenStreetMap tile is
  # fetched during the suite. What is tested here is the list and its filters;
  # the map's payload is asserted in the integration test.
  setup { page.driver.browser.manage.window.resize_to(1100, 900) }

  test "a visitor browses the directory and opens a shop" do
    visit root_path
    click_on I18n.t("nav.printers")

    assert_selector "h1", text: displayed("public.printers.index.title")
    assert_text shown(printers(:rennes).name)
    assert_text shown(printers(:lyon).name)
    assert_no_text shown(printers(:brouillon).name)

    find("a[href='#{printer_path(printers(:rennes))}']").click

    assert_selector "h1", text: shown(printers(:rennes).name)
    assert_text printers(:rennes).description
    assert_text displayed("enums.printer_technique.technique.screen_printing")
  end

  test "filtering by technique narrows the list" do
    visit printers_path

    check "technique_embroidery"

    assert_text shown(printers(:nantes).name)
    assert_no_text shown(printers(:rennes).name)
  end

  test "a printer fills in their listing and submits it, and an administrator publishes it" do
    sign_in users(:printer_draft)
    assert_current_path workshop_dashboard_path

    visit edit_workshop_profile_path
    assert_selector "h1", text: displayed("workshop.profiles.edit.heading")

    fill_in I18n.t("activerecord.attributes.printer.description"), with: "Sérigraphie, petites séries, textile bio."
    fill_in I18n.t("activerecord.attributes.printer.address"), with: "2 rue du Change"
    fill_in I18n.t("activerecord.attributes.printer.postal_code"), with: "37000"
    fill_in I18n.t("activerecord.attributes.printer.city"), with: "Tours"
    click_on I18n.t("workshop.profiles.edit.save")

    assert_text displayed("workshop.profiles.update.saved")

    click_on I18n.t("workshop.profiles.edit.submit_action")

    assert_text displayed("workshop.profiles.submit.submitted")
    assert_predicate printers(:brouillon).reload, :pending_review?

    # Not in the directory yet: publication is the administration's decision,
    # never the printer's.
    visit printers_path
    assert_no_text shown(printers(:brouillon).name)

    sign_out_from(workshop_dashboard_path)

    sign_in users(:admin)
    visit admin_printers_path
    assert_selector "h1", text: displayed("admin.printers.index.heading")

    within("li", text: shown(printers(:brouillon).name)) do
      click_on I18n.t("admin.printers.row.publish")
    end

    # Wait for the page to come back before reading the database: otherwise the
    # assertion races the request it just triggered.
    assert_text displayed("admin.printers.update.published", name: printers(:brouillon).name)
    assert_predicate printers(:brouillon).reload, :published?

    sign_out_from(admin_dashboard_path)
    visit printers_path

    assert_text shown(printers(:brouillon).name)
  end

  private
    def sign_in(user)
      visit new_session_path
      fill_in I18n.t("activerecord.attributes.user.email_address"), with: user.email_address
      fill_in I18n.t("activerecord.attributes.user.password"), with: "motdepasse-test"
      click_on I18n.t("sessions.new.submit")

      # Wait for the session to actually open: returning early lets the next
      # `visit` race the redirect, and the test then fails somewhere else
      # entirely.
      assert_no_current_path new_session_path
    end

    # Signing out happens from a professional space: the public header offers a
    # link to the space, not a sign-out button.
    def sign_out_from(path)
      visit path
      click_on I18n.t("nav.sign_out")
      assert_current_path root_path
    end
end
