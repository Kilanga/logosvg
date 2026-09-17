require "application_system_test_case"

class VisitingHomePageTest < ApplicationSystemTestCase
  test "a print shop sees what the platform turns a prompt into" do
    visit root_path

    assert_selector "h1", text: displayed("public.home.show.headline_lead")

    # The before / after pair is the argument: a raster image on one side,
    # separated flat inks on the other.
    assert_selector "figure", count: 2
    assert_text displayed("public.home.demo.before_label")
    assert_text displayed("public.home.demo.after_label")

    # One swatch per screen, each labelled with the ink code.
    assert_text "#1F5F7A"
    assert_text "#E4572E"
    assert_text "#F2C14E"
    assert_text displayed("public.home.demo.after_screens", count: 3)
  end

  test "the hero leads to the explanation of how it works" do
    visit root_path

    click_on I18n.t("public.home.show.cta_secondary")

    assert_selector "#fonctionnement h2", text: displayed("public.home.show.how.title")
  end

  test "the order email is shown with its attachments and confirmation button" do
    visit root_path

    assert_text displayed("public.home.show.email.title")
    assert_text "design.svg"
    assert_text displayed("public.home.show.email.confirm_button")
  end
end
