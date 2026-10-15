require "test_helper"

# G2, reported on 15/10/2026: the watermarked preview, blown up to the print
# size, went through as a designer's version.
class WatermarkCheckTest < ActiveSupport::TestCase
  setup do
    @design = reviews(:in_progress).design
    @design.print_file.attach(io: StringIO.new(picture.write_to_buffer(".png")),
                              filename: "print.png", content_type: "image/png")
  end

  test "the preview blown up to print size is caught" do
    preview = Vips::Image.new_from_buffer(DesignPreview.call(@design), "")
    blown_up = preview.resize(2953.0 / preview.width).write_to_buffer(".png")

    assert_equal true, WatermarkCheck.call(@design, blown_up)
  end

  test "the original, untouched or retouched, is not" do
    assert_equal false, WatermarkCheck.call(@design, picture.write_to_buffer(".png"))

    retouched = (picture * 0.9 + 12).cast(:uchar).write_to_buffer(".png")
    assert_equal false, WatermarkCheck.call(@design, retouched)
  end

  test "a picture redrawn from scratch is not" do
    other = (Vips::Image.sines(1500, 1500, hfreq: 2, vfreq: 9) * 120 + 128).cast(:uchar)
    other = other.bandjoin([ other.rot(:d90), other ]).copy(interpretation: :srgb)

    assert_equal false, WatermarkCheck.call(@design, other.write_to_buffer(".png"))
  end

  test "nothing to compare with says so" do
    assert_nil WatermarkCheck.call(Design.new, picture.write_to_buffer(".png"))
  end

  private
    # Colour and detail everywhere, like a real design: a flat picture would
    # make any mark obvious and the test too easy.
    def picture
      @picture ||= begin
        red = (Vips::Image.sines(1500, 1500, hfreq: 3, vfreq: 1) * 100 + 128)
        green = (Vips::Image.sines(1500, 1500, hfreq: 1, vfreq: 4) * 100 + 128)
        blue = (Vips::Image.gaussnoise(1500, 1500, sigma: 30, mean: 128))
        red.bandjoin([ green, blue ]).cast(:uchar).copy(interpretation: :srgb)
      end
    end
end
