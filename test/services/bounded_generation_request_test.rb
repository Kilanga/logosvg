require "test_helper"

# Two ceilings, in order: the technique's, then the shop's. Lowering silently is
# the point — the alternative is refusing a form over a limit the client never
# saw.
class BoundedGenerationRequestTest < ActiveSupport::TestCase
  test "a shop with fewer screens than the client asked for lowers the count" do
    bounded = call(technique: "screen_printing", colors_requested: 6, printer: printers(:rennes))

    assert_equal 4, bounded[:colors_requested], "Rennes prints four screens at most"
  end

  test "what fits is left exactly as it was asked" do
    bounded = call(technique: "screen_printing", colors_requested: 3, printer: printers(:rennes))

    assert_equal 3, bounded[:colors_requested]
  end

  test "with no shop in context the catalogue's own ceiling applies" do
    bounded = call(technique: "screen_printing", colors_requested: 99, printer: nil)

    assert_equal PrintTechniques.fetch("screen_printing").max_colors, bounded[:colors_requested]
  end

  # Sending a colour count for a technique that prints a full image would state a
  # limit the machine has not got.
  test "a technique that counts no inks sends no colours at all" do
    bounded = call(technique: "dtf", colors_requested: 4, printer: printers(:lyon))

    assert_nil bounded[:colors_requested]
  end

  test "a missing colour count falls back to what the technique suggests" do
    bounded = call(technique: "screen_printing", colors_requested: nil, printer: nil)

    assert_equal PrintTechniques.fetch("screen_printing").default_colors, bounded[:colors_requested]
  end

  test "zero colours is not a design: one ink is the floor" do
    bounded = call(technique: "screen_printing", colors_requested: 0, printer: printers(:rennes))

    assert_equal 1, bounded[:colors_requested]
  end

  test "a width beyond the shop's press comes back at the press's width" do
    bounded = call(technique: "screen_printing", colors_requested: 2,
                   print_width_cm: 50, printer: printers(:rennes))

    assert_equal 30, bounded[:print_width_cm]
  end

  test "a width nobody has a ceiling for is left alone" do
    bounded = call(technique: "screen_printing", colors_requested: 2,
                   print_width_cm: 18, printer: nil)

    assert_equal 18, bounded[:print_width_cm]
  end

  # A stale form, a renamed technique: nothing to bound against, and the model's
  # own validation is what refuses it.
  test "a technique the catalogue does not know passes through untouched" do
    attributes = { technique: "lithographie", colors_requested: 9 }

    assert_equal attributes, BoundedGenerationRequest.call(attributes: attributes, printer: nil)
  end

  private
    def call(printer:, **attributes)
      BoundedGenerationRequest.call(attributes: attributes, printer: printer)
    end
end
