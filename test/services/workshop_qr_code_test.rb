require "test_helper"

class WorkshopQrCodeTest < ActiveSupport::TestCase
  URL = "https://exemple.invalid/a/serigraphie-du-thabor".freeze

  test "the svg is a standalone document, so it prints at any size" do
    svg = WorkshopQrCode.svg(URL)

    assert_match(/\A<\?xml/, svg)
    assert_match(/<svg/, svg)
    assert_match(/viewBox/, svg)
  end

  test "the png is a png" do
    assert_equal "\x89PNG".b, WorkshopQrCode.png(URL).byteslice(0, 4)
  end

  test "the code actually carries the url" do
    decoded = RQRCode::QRCode.new(URL, level: WorkshopQrCode::ERROR_CORRECTION)

    assert_equal decoded.to_s, RQRCode::QRCode.new(URL, level: :h).to_s
  end

  # A poster on a counter gets coffee on it. `H` corrects up to 30% of the
  # symbol, which is what makes that survivable.
  test "the correction level is the high one" do
    assert_equal :h, WorkshopQrCode::ERROR_CORRECTION
  end

  test "the svg honours the size it is asked for" do
    assert_match(/width="320"/, WorkshopQrCode.svg(URL, size: 320))
  end

  # The SVG is rendered inline on the poster, so it must survive the same
  # inspection as any other SVG this application serves.
  test "the generated svg passes our own inspection" do
    assert_predicate SvgInspector.call(WorkshopQrCode.svg(URL)), :valid?
  end
end
