require "application_system_test_case"

class FinishingTest < ApplicationSystemTestCase
  # Below the breakpoint that reveals the map, so no OpenStreetMap tile is
  # fetched during the suite.
  setup { page.driver.browser.manage.window.resize_to(1100, 900) }

  # The completion criterion of step 10: the whole chain is walkable, and every
  # document a visitor is entitled to read is reachable from any page.
  test "a visitor reads the legal pages from the footer" do
    visit root_path

    click_on I18n.t("legal.privacy.title")

    assert_selector "h1", text: displayed("legal.privacy.title")
    assert_text displayed("legal.draft_title")

    # Each page carries the others, so none is a dead end.
    click_on I18n.t("legal.ranking.title"), match: :first

    assert_selector "h1", text: displayed("legal.ranking.title")
    assert_text displayed("legal.ranking.featured.title")
  end

  # The download itself is asserted in the integration test, where the
  # response body can actually be read: a browser download does not navigate,
  # so there is nothing here for Capybara to look at afterwards.
  test "a client finds the way to export their data" do
    sign_in users(:client)
    visit client_account_path

    assert_text displayed("client.accounts.edit.export_body")
    assert_link I18n.t("client.accounts.edit.export"), href: client_account_export_path
  end

  test "a client closes their account, and is told what survives" do
    sign_in users(:client)
    visit client_account_path

    assert_text displayed("client.accounts.edit.close_kept",
                          days: Rails.application.config.tshirt.privacy[:deleted_account_purge_days])

    fill_in "current_password", with: "motdepasse-test"
    accept_confirm { click_on I18n.t("client.accounts.edit.close_action") }

    assert_text displayed("client.accounts.destroy.closed")
    assert_not_predicate users(:client).reload, :active?

    # And the workshop still has its job.
    assert PrintRequest.exists?(print_requests(:waiting).id)
  end

  # Checked where it is easy to lose and cheap to keep.
  test "every space offers a way past the navigation" do
    sign_in users(:client)

    assert_selector "a.skip-link", visible: :all

    visit printers_path

    assert_selector "a.skip-link", visible: :all
  end

  private
    def sign_in(user)
      visit new_session_path
      fill_in I18n.t("activerecord.attributes.user.email_address"), with: user.email_address
      fill_in I18n.t("activerecord.attributes.user.password"), with: "motdepasse-test"
      click_on I18n.t("sessions.new.submit")

      assert_no_current_path new_session_path
    end
end
