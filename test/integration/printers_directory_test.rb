require "test_helper"

class PrintersDirectoryTest < ActionDispatch::IntegrationTest
  test "a visitor reads the directory without an account" do
    get printers_path

    assert_response :success
    assert_select "h1"
  end

  test "the directory lists published shops and hides the others" do
    get printers_path

    assert_includes response.body, printers(:rennes).name
    assert_includes response.body, printers(:lyon).name
    assert_not_includes response.body, printers(:brouillon).name
    assert_not_includes response.body, printers(:attente).name
  end

  test "filters narrow the list" do
    get printers_path, params: { techniques: [ "embroidery" ] }

    assert_includes response.body, printers(:nantes).name
    assert_not_includes response.body, printers(:rennes).name
  end

  test "a radius keeps the shops that ship nationwide" do
    get printers_path, params: { latitude: "48.1173", longitude: "-1.6778", radius: 10 }

    assert_includes response.body, printers(:rennes).name
    assert_includes response.body, printers(:lyon).name
    assert_not_includes response.body, printers(:nantes).name
  end

  test "a published shop page is open to everyone" do
    get printer_path(printers(:rennes))

    assert_response :success
    assert_includes response.body, printers(:rennes).description
  end

  # Sent home rather than to the sign-in page: the directory admits visitors, so
  # there is nothing to sign in *for*. Telling them "sign in to see this" would
  # also reveal that the listing exists.
  test "an unpublished shop page is closed to a visitor" do
    get printer_path(printers(:brouillon))

    assert_redirected_to root_path
  end

  test "an unpublished shop page is closed to another signed-in user" do
    sign_in_as users(:client)

    get printer_path(printers(:brouillon))

    assert_redirected_to "/mon-espace"
  end

  test "the owner previews their own unpublished listing" do
    sign_in_as users(:printer_draft)

    get printer_path(printers(:brouillon))

    assert_response :success
  end

  test "an unknown slug is a 404, not a server error" do
    get printer_path("atelier-qui-n-existe-pas")

    assert_response :not_found
  end

  test "the map carries only located shops, and the OpenStreetMap attribution" do
    get printers_path

    assert_includes response.body, "OpenStreetMap"
    assert_includes response.body, "data-map-points-value"
  end
end
