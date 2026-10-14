require "test_helper"

# Reported on 14/10/2026: the Atelier+ brand colour had no field anywhere.
class BrandColorTest < ActionDispatch::IntegrationTest
  test "a shop sets its brand colour from its listing" do
    sign_in_as users(:printer)

    get edit_workshop_profile_path
    assert_select "input[type=color][name=?]", "printer[brand_color]"

    patch workshop_profile_path, params: { printer: { brand_color: "#c0392b" } }

    assert_redirected_to edit_workshop_profile_path
    assert_equal "#c0392b", printers(:rennes).reload.brand_color.downcase
  end

  test "with Atelier+, the creation screen wears the shop's colour" do
    rennes = printers(:rennes)
    rennes.update_columns(brand_color: "#C0392B", featured: true)
    rennes.subscription.update_columns(plan: "atelier_plus", status: "active")
    sign_in_as users(:client)

    get new_design_path

    assert_select "#workshop_band[style*=?]", rennes.brand_palette.base
  end

  test "without Atelier+, the creation screen keeps the platform's colours" do
    rennes = printers(:rennes)
    rennes.update_columns(brand_color: "#C0392B", featured: false)
    sign_in_as users(:client)

    get new_design_path

    assert_select "#workshop_band"
    assert_select "#workshop_band[style]", count: 0
  end
end
