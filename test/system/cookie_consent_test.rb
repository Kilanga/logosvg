require "application_system_test_case"

class CookieConsentSystemTest < ApplicationSystemTestCase
  setup { page.driver.browser.manage.window.resize_to(1100, 900) }

  test "a visitor sent by a shop is asked once, and the answer holds" do
    visit workshop_link_path(slug: printers(:lyon).slug)

    within "section[aria-labelledby=consent-title]" do
      assert_text displayed("consent.title")
      click_on I18n.t("consent.accept")
    end

    assert_text displayed("public.cookie_consents.create.accepted")
    assert_no_selector "section[aria-labelledby=consent-title]"

    # Reloading is not asking again.
    visit current_path
    assert_no_selector "section[aria-labelledby=consent-title]"
  end

  test "refusing is as short a road as accepting, and can be undone from the footer" do
    visit workshop_link_path(slug: printers(:lyon).slug)
    click_on I18n.t("consent.decline")

    assert_text displayed("public.cookie_consents.create.declined")

    click_on I18n.t("legal.cookies.title"), match: :first
    assert_text displayed("legal.cookies.choice.state.declined")

    click_on I18n.t("consent.accept")
    assert_text displayed("legal.cookies.choice.state.accepted",
                          days: Rails.application.config.tshirt.privacy[:attribution_cookie_days])
  end

  test "someone who walked in by the front door is never asked" do
    visit root_path

    assert_no_selector "section[aria-labelledby=consent-title]"
  end
end
