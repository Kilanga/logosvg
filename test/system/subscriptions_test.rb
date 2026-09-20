require "application_system_test_case"

class SubscriptionsTest < ApplicationSystemTestCase
  # Below the breakpoint that reveals the map, so no OpenStreetMap tile is
  # fetched during the suite.
  setup { page.driver.browser.manage.window.resize_to(1100, 900) }

  # The completion criterion of step 6, walked rather than asserted on a scope.
  test "a shop that stops paying disappears from the directory" do
    visit printers_path

    assert_text shown(printers(:rennes).name)

    subscriptions(:rennes).update!(status: "canceled")
    visit printers_path

    assert_no_text shown(printers(:rennes).name)
    # The shops that do pay are untouched. No message here: `assert_text` reads
    # a second positional argument as the text type, not as a failure message.
    assert_text shown(printers(:lyon).name)
  end

  test "a printer whose subscription lapsed is told so on their dashboard" do
    subscriptions(:rennes).update!(status: "canceled")
    sign_in users(:printer)

    assert_text displayed("workshop.dashboards.show.not_visible")

    click_on I18n.t("nav.subscription")

    assert_text displayed("workshop.subscriptions.show.not_visible")
    assert_text displayed("enums.subscription.plan.atelier_plus")
  end

  test "a paying printer sees their plan and the way into the portal" do
    sign_in users(:printer)
    visit workshop_subscription_path

    assert_text displayed("enums.subscription.plan.listing")
    assert_text displayed("enums.subscription.status.active")
    assert_button I18n.t("workshop.subscriptions.show.open_portal")
  end

  # A failed payment does not take the listing down the same day, and the
  # useful thing to say is exactly when it will.
  test "a failed payment says when the listing goes dark" do
    subscriptions(:rennes).update!(status: "past_due", past_due_since: 1.day.ago)
    sign_in users(:printer)
    visit workshop_subscription_path

    assert_text displayed("workshop.subscriptions.show.past_due_title")
    assert_text shown(I18n.l(subscriptions(:rennes).hidden_from.to_date, format: :long))
  end

  test "a printer finds their link, their code and their poster" do
    sign_in users(:printer)
    click_on I18n.t("nav.my_link")

    # The address sits in a readonly field, so it is a value and not text.
    assert_field with: workshop_link_url(slug: printers(:rennes).slug)
    assert_selector "svg"

    click_on I18n.t("workshop.links.show.poster")

    within_window(windows.last) do
      assert_text displayed("workshop.links.poster.headline")
      assert_selector "svg"
      assert_text shown(printers(:rennes).name)
    end
  end

  test "statistics are what Atelier+ buys" do
    sign_in users(:printer)
    visit workshop_link_share_path

    assert_text displayed("workshop.links.show.statistics_locked")

    sign_out
    sign_in users(:printer_lyon)
    visit workshop_link_share_path

    assert_text displayed("workshop.links.show.statistics")
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
