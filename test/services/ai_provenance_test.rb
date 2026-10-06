require "test_helper"

# Article 50(2) of the AI Act: every file the platform produces says, in a form
# machines read, that a generative model drew it. Invisible on purpose — the
# print file must print exactly as before.
class AiProvenanceTest < ActiveSupport::TestCase
  test "a png gains an xmp chunk right after IHDR, and stays a valid png" do
    marked = AiProvenance.mark(png, content_type: "image/png")

    assert_equal "\x89PNG\r\n\x1a\n".b, marked.byteslice(0, 8)
    assert_equal "iTXt", marked.byteslice(33 + 4, 4), "the XMP chunk must follow IHDR"
    assert_includes marked, "XML:com.adobe.xmp"
    assert_includes marked, "#{AiProvenance::SOURCE_TYPE_URI}trainedAlgorithmicMedia"

    image = Vips::Image.new_from_buffer(marked, "")
    assert_equal [ 1, 1 ], [ image.width, image.height ]
  end

  test "the png chunk carries a correct crc" do
    marked = AiProvenance.mark(png, content_type: "image/png").b
    length = marked.byteslice(33, 4).unpack1("N")
    type_and_data = marked.byteslice(37, 4 + length)
    crc = marked.byteslice(41 + length, 4).unpack1("N")

    assert_equal Zlib.crc32(type_and_data), crc
  end

  test "the pixels are not touched" do
    before = Vips::Image.new_from_buffer(png, "")
    after = Vips::Image.new_from_buffer(AiProvenance.mark(png, content_type: "image/png"), "")

    assert_equal before.write_to_memory, after.write_to_memory
  end

  test "an svg gains a metadata element and still passes the inspector, with the same inks" do
    marked = AiProvenance.mark(svg, content_type: "image/svg+xml")
    inspection = SvgInspector.call(marked)

    assert inspection.valid?, "refused: #{inspection.reason}"
    assert_equal SvgInspector.call(svg).fills, inspection.fills
    assert_includes marked, %(<metadata id="ai-provenance">)
    assert_includes marked, "trainedAlgorithmicMedia"
  end

  test "an svg is still rendered by libvips once marked" do
    marked = AiProvenance.mark(svg, content_type: "image/svg+xml")

    assert_equal 100, Vips::Image.new_from_buffer(marked, "").width
  end

  test "marking is idempotent" do
    once = AiProvenance.mark(png, content_type: "image/png")

    assert_equal once, AiProvenance.mark(once, content_type: "image/png")
    assert_equal 1, once.scan("XML:com.adobe.xmp").size
  end

  test "a designer's delivery is marked as reworked, not as raw generation" do
    marked = AiProvenance.mark(svg, content_type: "image/svg+xml", kind: AiProvenance::EDITED)

    assert_includes marked, "compositeWithTrainedAlgorithmicMedia"
  end

  test "anything else comes back untouched" do
    assert_equal "%PDF-1.4", AiProvenance.mark("%PDF-1.4", content_type: "application/pdf")
    assert_equal "pas un png", AiProvenance.mark("pas un png", content_type: "image/png")
  end

  private
    def svg
      %(<?xml version="1.0"?>\n<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 10 10">) +
        %(<path d="M0 0h5v10H0z" fill="#1F5F7A"/><path d="M5 0h5v10H5z" fill="#e4f2ea"/></svg>)
    end

    def png
      Base64.decode64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )
    end
end
