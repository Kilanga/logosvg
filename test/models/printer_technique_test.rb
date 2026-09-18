require "test_helper"

class PrinterTechniqueTest < ActiveSupport::TestCase
  test "a shop declares each technique once" do
    duplicate = printers(:rennes).techniques.build(technique: "screen_printing", max_colors: 2)

    assert_not duplicate.valid?
    assert duplicate.errors.include?(:technique)
  end

  test "techniques applied colour by colour need a ceiling" do
    %w[ screen_printing flex embroidery ].each do |technique|
      row = PrinterTechnique.new(printer: printers(:brouillon), technique: technique)

      assert_not row.valid?, "#{technique} should require a colour ceiling"
      assert row.errors.include?(:max_colors)
    end
  end

  test "full-colour techniques need none" do
    %w[ dtf dtg ].each do |technique|
      row = PrinterTechnique.new(printer: printers(:brouillon), technique: technique,
                                 accepted_formats: %w[ svg ])

      assert row.valid?, "#{technique} should not require a colour ceiling"
    end
  end

  test "a ceiling stays within what a shop can physically do" do
    row = PrinterTechnique.new(printer: printers(:brouillon), technique: "screen_printing", max_colors: 40)

    assert_not row.valid?
    assert row.errors.include?(:max_colors)
  end

  test "printing depends on the ink count for screen printing" do
    technique = printer_techniques(:rennes_screen)

    assert technique.prints?(3)
    assert technique.prints?(4), "four inks on a four-colour press is exactly right"
    assert_not technique.prints?(5)
  end

  test "printing is unconditional for DTF, whatever the ink count" do
    assert printer_techniques(:lyon_dtf).prints?(12)
  end

  test "a technique that does not take SVG cannot print anything here" do
    technique = printer_techniques(:rennes_screen)
    technique.accepted_formats = %w[ pdf ]

    assert_not technique.prints?(1), "the platform only ever sends an SVG"
  end

  test "a technique outside the five is refused" do
    row = PrinterTechnique.new(printer: printers(:brouillon), technique: "lithographie")

    assert_not row.valid?
    assert row.errors.include?(:technique)
  end
end
