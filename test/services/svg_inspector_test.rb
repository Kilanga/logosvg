require "test_helper"

# Every refusal here is a way an SVG has actually been used to attack a server
# or a visitor. See docs/SPEC.md, "Fichiers".
class SvgInspectorTest < ActiveSupport::TestCase
  test "a plain flat-colour drawing passes, and its inks are counted" do
    result = SvgInspector.call(svg(<<~SHAPES))
      <rect fill="#1F5F7A" width="10" height="10"/>
      <circle fill="#E4572E" r="5"/>
      <path fill="#1F5F7A" d="M0 0 L1 1"/>
    SHAPES

    assert_predicate result, :valid?
    assert_equal 2, result.inks, "the same fill twice is one ink, and one screen"
    assert_equal [ "#1f5f7a", "#e4572e" ], result.fills
  end

  test "fill none is not an ink" do
    result = SvgInspector.call(svg(%(<rect fill="none" width="1" height="1"/><rect fill="#000000"/>)))

    assert_equal 1, result.inks
  end

  test "a script is refused" do
    result = SvgInspector.call(svg(%(<script>alert(1)</script>)))

    assert_not_predicate result, :valid?
    assert_equal :forbidden_element, result.reason
  end

  test "a foreignObject is refused: it carries arbitrary HTML" do
    assert_equal :forbidden_element, SvgInspector.call(svg("<foreignObject><p>x</p></foreignObject>")).reason
  end

  test "an event handler attribute is refused" do
    assert_equal :event_handler, SvgInspector.call(svg(%(<rect onload="alert(1)"/>))).reason
  end

  test "a javascript URL is refused" do
    assert_equal :external_reference, SvgInspector.call(svg(%(<a href="javascript:alert(1)"><rect/></a>))).reason
  end

  test "a remote reference is refused: it would call out from the visitor's browser" do
    assert_equal :forbidden_element,
                 SvgInspector.call(svg(%(<image href="https://ailleurs.example/pixel.png"/>))).reason
  end

  # An attribute is not the only place a URL hides. The renderer that rasterises
  # the file — librsvg, through libvips — honours stylesheets, so a remote one
  # would be fetched by the server itself, not by a browser.
  test "a remote stylesheet is refused" do
    assert_equal :external_reference,
                 SvgInspector.call(svg(%(<style>@import url("https://ailleurs.example/x.css");</style>))).reason
  end

  test "a url() reaching out of the document from a stylesheet is refused" do
    assert_equal :external_reference,
                 SvgInspector.call(svg(%(<style>rect { fill: url(http://ailleurs.example/p.svg); }</style>))).reason
  end

  test "a remote url in an inline style attribute is refused" do
    assert_equal :external_reference,
                 SvgInspector.call(svg(%(<rect style="fill: url(//ailleurs.example/p.svg)"/>))).reason
  end

  test "a stylesheet that stays inside the document is fine" do
    result = SvgInspector.call(svg(%(<style>rect { fill: #1F5F7A; }</style><rect fill="#1F5F7A"/>)))

    assert_predicate result, :valid?
  end

  # The billion laughs: a handful of nested entities expanding into gigabytes.
  test "entities are refused outright rather than expanded" do
    source = <<~XML
      <?xml version="1.0"?>
      <!DOCTYPE svg [<!ENTITY lol "lol"><!ENTITY lol2 "&lol;&lol;&lol;">]>
      <svg xmlns="http://www.w3.org/2000/svg">&lol2;</svg>
    XML

    assert_equal :entity, SvgInspector.call(source).reason
  end

  test "a document whose root is not svg is refused" do
    assert_equal :not_svg, SvgInspector.call("<html><body>bonjour</body></html>").reason
  end

  test "something that is not XML at all is refused" do
    assert_equal :not_svg, SvgInspector.call("ceci n'est pas un fichier").reason
  end

  test "an empty file is refused" do
    assert_equal :empty, SvgInspector.call("").reason
  end

  test "a file beyond the size limit is refused before being parsed" do
    result = SvgInspector.call("<svg>#{'a' * SvgInspector::MAX_BYTES}</svg>")

    assert_equal :too_large, result.reason
  end

  private
    def svg(inner)
      %(<?xml version="1.0"?><svg xmlns="http://www.w3.org/2000/svg">#{inner}</svg>)
    end
end
