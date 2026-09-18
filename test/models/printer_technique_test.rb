require "test_helper"

class PrinterTechniqueTest < ActiveSupport::TestCase
  test "a shop declares each technique once" do
    duplicate = printers(:rennes).techniques.build(technique: "screen_printing", max_colors: 2)

    assert_not duplicate.valid?
    assert duplicate.errors.include?(:technique)
  end

  test "a technique the catalogue does not know is refused" do
    row = build_row(technique: "lithographie")

    assert_not row.valid?
    assert row.errors.include?(:technique)
  end

  # The shop's own wording is the point of the model: two shops doing the same
  # technique may present it very differently.
  test "the shop's label wins, and the catalogue's is the default" do
    assert_equal "Broderie fil à fil", printer_techniques(:nantes_embroidery).display_label
    assert_equal "Sérigraphie", printer_techniques(:rennes_screen).display_label
  end

  test "a blank label falls back rather than showing nothing" do
    row = printer_techniques(:nantes_embroidery)
    row.update!(label: "   ")

    assert_nil row.label
    assert_equal "Broderie", row.display_label
  end

  test "a shop names the file its machine expects, whatever the catalogue does" do
    sublimation = printer_techniques(:nantes_sublimation)

    assert_equal "raster", sublimation.catalogue.family
    assert_equal "png", sublimation.catalogue.native_format
    assert_equal "svg", sublimation.output_format, "the shop asked for an SVG and gets one"
  end

  test "a format outside the three is refused" do
    assert_not build_row(output_format: "tiff").valid?
  end

  test "a colour space outside the two is refused" do
    assert_not build_row(color_space: "pantone").valid?
    assert build_row(color_space: "cmyk").valid?
  end

  test "techniques applied colour by colour need a ceiling" do
    %w[ screen_printing flex embroidery ].each do |key|
      row = build_row(technique: key, max_colors: nil)

      assert_not row.valid?, "#{key} should require a colour ceiling"
      assert row.errors.include?(:max_colors)
    end
  end

  test "full-colour techniques must not carry one" do
    %w[ dtf dtg sublimation ].each do |key|
      row = build_row(technique: key, max_colors: 4)

      assert_not row.valid?, "#{key} prints every colour at once and has no ceiling"
      assert row.errors.include?(:max_colors)
    end
  end

  # The catalogue's ceiling is what the generator will accept anyway: a shop
  # cannot declare eight screens and expect eight-ink designs.
  test "a ceiling above the catalogue's is refused" do
    assert_not build_row(technique: "flex", max_colors: 3).valid?, "flex tops out at 2"
    assert build_row(technique: "flex", max_colors: 2).valid?
    assert_not build_row(technique: "screen_printing", max_colors: 7).valid?
    assert build_row(technique: "screen_printing", max_colors: 6).valid?
  end

  test "printing depends on the ink count where inks are counted" do
    technique = printer_techniques(:rennes_screen)

    assert technique.prints_inks?(3)
    assert technique.prints_inks?(4), "four inks on a four-colour press is exactly right"
    assert_not technique.prints_inks?(5)
  end

  test "printing is unconditional where the machine prints every colour at once" do
    assert printer_techniques(:lyon_dtf).prints_inks?(12)
  end

  test "blank dimensions fall back to the listing's own maximum" do
    row = printer_techniques(:nantes_flex)

    assert_nil row.max_print_width_cm
    assert_equal printers(:nantes).max_print_width_cm, row.effective_max_width_cm
  end

  test "declared dimensions win over the listing's" do
    assert_equal 20, printer_techniques(:nantes_embroidery).effective_max_width_cm
  end

  test "a width beyond the limit is refused, a blank one never is" do
    row = printer_techniques(:nantes_embroidery)

    assert row.prints_width?(20)
    assert_not row.prints_width?(21)
    assert row.prints_width?(nil), "a design with no stated width is not judged on width"
  end

  private
    def build_row(**attributes)
      printers(:brouillon).techniques.build({
        technique: "screen_printing",
        max_colors: 4,
        output_format: "svg",
        color_space: "rgb"
      }.merge(attributes))
    end
end
