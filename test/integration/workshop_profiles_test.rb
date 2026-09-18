require "test_helper"

class WorkshopProfilesTest < ActionDispatch::IntegrationTest
  test "a printer with no listing still gets a form" do
    sign_in_as users(:printer_waiting).tap { |u| u.printer.destroy }

    get edit_workshop_profile_path

    assert_response :success
  end

  test "the orders address defaults to the account address" do
    user = users(:printer_waiting)
    user.printer.destroy
    sign_in_as user

    get edit_workshop_profile_path

    assert_select "input[name=?][value=?]", "printer[orders_email]", user.email_address
  end

  test "a printer edits their own listing" do
    sign_in_as users(:printer)

    patch workshop_profile_path, params: { printer: { name: "Sérigraphie du Thabor", price_note: "Dès 12 €" } }

    assert_redirected_to edit_workshop_profile_path
    assert_equal "Dès 12 €", printers(:rennes).reload.price_note
  end

  test "an invalid listing comes back with its errors rather than silently failing" do
    sign_in_as users(:printer)

    patch workshop_profile_path, params: { printer: { name: "", postal_code: "abc" } }

    assert_response :unprocessable_entity
    assert_equal "Sérigraphie du Thabor", printers(:rennes).reload.name
  end

  test "a printer never reaches another shop's listing" do
    sign_in_as users(:printer_lyon)

    patch workshop_profile_path, params: { printer: { name: "Renommé par quelqu'un d'autre" } }

    assert_equal "Sérigraphie du Thabor", printers(:rennes).reload.name
    assert_equal "Renommé par quelqu'un d'autre", printers(:lyon).reload.name
  end

  test "only a printer reaches the listing form" do
    [ :client, :designer, :admin ].each do |role|
      sign_in_as users(role)
      get edit_workshop_profile_path

      assert_response :redirect, "#{role} must not open the listing form"

      sign_out
    end
  end

  test "a draft too empty to be judged is not submitted" do
    sign_in_as users(:printer_draft)

    post submit_workshop_profile_path

    assert_predicate printers(:brouillon).reload, :draft?
  end

  test "a complete draft is submitted for review, and publication is not the printer's call" do
    sign_in_as users(:printer_draft)

    patch workshop_profile_path, params: { printer: {
      name: "Atelier en préparation", description: "Sérigraphie, petites séries.",
      address: "2 rue du Change", postal_code: "37000", city: "Tours",
      orders_email: "futur@example.invalid"
    } }

    post submit_workshop_profile_path

    assert_predicate printers(:brouillon).reload, :pending_review?
    assert_not_predicate printers(:brouillon), :published?
  end

  test "a listing already waiting cannot be submitted again" do
    sign_in_as users(:printer_waiting)

    post submit_workshop_profile_path

    assert_response :redirect
    assert_predicate printers(:attente).reload, :pending_review?
  end

  test "changing the address queues the shop for geocoding" do
    sign_in_as users(:printer)

    assert_enqueued_with job: GeocodePrinterJob do
      patch workshop_profile_path, params: { printer: { city: "Saint-Malo" } }
    end
  end
end
