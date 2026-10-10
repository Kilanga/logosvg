require "test_helper"

# What a technique did to a client's own picture, said beside the proof. Read
# from what the service recorded: inks for a vector file, size, resolution and
# enlargement for a raster one.
class DesignsHelperTest < ActionView::TestCase
  test "a vector rendering says the picture became a few flat inks" do
    design = designs(:fox_screen)

    changes = print_changes(design)

    assert_includes changes, I18n.t("designs.changes.flattened", count: 3)
    assert_includes changes, I18n.t("designs.changes.traced")
    assert_includes changes, I18n.t("designs.changes.width", width: 25)
    assert_not_includes changes, I18n.t("designs.changes.kept_whole")
  end

  test "a raster rendering says the picture is kept whole, and how far it was enlarged" do
    design = designs(:fox_dtf)
    design.stats = design.stats.merge("print_width_cm" => 24, "print_height_cm" => 18, "upscale" => 2.4)

    changes = print_changes(design)

    assert_includes changes, I18n.t("designs.changes.kept_whole")
    assert_includes changes, I18n.t("designs.changes.raster_size", width: 24, height: 18, dpi: 300)
    assert_includes changes, I18n.t("designs.changes.enlarged", factor: "2,4")
    assert_not_includes changes, I18n.t("designs.changes.traced")
  end

  test "the background is said removed or kept, as the client chose" do
    design = designs(:fox_dtf)

    design.remove_background = true
    assert_includes print_changes(design), I18n.t("designs.changes.background_removed")

    design.remove_background = false
    assert_includes print_changes(design), I18n.t("designs.changes.background_kept")
  end

  test "trying another technique is offered only where the shop has another" do
    assert_not other_techniques_offered?(designs(:fox_screen)), "Rennes prints only screen printing"
    assert other_techniques_offered?(designs(:pending_design)), "no shop: every technique"
  end
end
