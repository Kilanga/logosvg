require "test_helper"

class BrandPaletteTest < ActiveSupport::TestCase
  test "a shop without a colour gets the platform's emulsion" do
    assert_equal "#1F5F7A", BrandPalette.new(nil).base
    assert_equal "#1F5F7A", BrandPalette.new("").base
  end

  test "white goes on a dark colour, ink on a pale one" do
    assert_equal BrandPalette::WHITE, BrandPalette.new("#2B50A8").on_base
    assert_equal BrandPalette::INK, BrandPalette.new("#E9B949").on_base
  end

  test "a dark colour is written as it is" do
    assert_equal "#2B50A8", BrandPalette.new("#2B50A8").text
  end

  test "a pale colour is darkened until it reads on white" do
    palette = BrandPalette.new("#E9B949")

    assert_not_equal "#E9B949", palette.text
    assert_operator contrast(palette.text, "#FFFFFF"), :>=, 4.5
  end

  test "every colour reads one way or the other" do
    %w[ #FFFFFF #FFFF00 #00FF00 #C2410C #808080 #000000 ].each do |colour|
      palette = BrandPalette.new(colour)

      assert_operator contrast(palette.base, palette.on_base), :>=, 4.5, colour
      assert_operator contrast(palette.text, "#FFFFFF"), :>=, 4.5, colour
    end
  end

  test "a middle tone on which nothing reads is taken just dark enough for white" do
    palette = BrandPalette.new("#808080")

    assert_not_equal "#808080", palette.base
    assert_equal BrandPalette::WHITE, palette.on_base
  end

  test "tints head towards white" do
    palette = BrandPalette.new("#2B50A8")

    assert_equal "#2B50A8", palette.tint(0)
    assert_equal "#FFFFFF", palette.tint(1)
  end

  private
    def contrast(a, b)
      palette = BrandPalette.new(a)
      palette.send(:contrast, palette.send(:rgb, a), palette.send(:rgb, b))
    end
end
