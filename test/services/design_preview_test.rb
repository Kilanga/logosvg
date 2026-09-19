require "test_helper"

# The one rendering a client ever receives. Everything here is about what the
# print file must *not* become on its way to them.
class DesignPreviewTest < ActiveSupport::TestCase
  setup { @design = designs(:fox_screen) }

  test "a design with no file has no preview" do
    assert_nil DesignPreview.call(designs(:pending_design))
  end

  # A screen-printing design *is* an SVG, and libvips refuses its SVG loader by
  # default — image_processing blocks every untrusted loader when it loads. Left
  # alone, every vector design would come back without a preview, and silently,
  # because the file itself stores perfectly well.
  test "a vector print file rasterises rather than coming back empty" do
    attach(svg, "design.svg", "image/svg+xml")

    preview = DesignPreview.call(@design)

    assert_not_nil preview, "the SVG loader is blocked — see config/initializers/vips.rb"
    assert_equal "\x89PNG".b, preview.byteslice(0, 4)
  end

  test "a raster print file rasterises too" do
    attach(png, "print.png", "image/png")

    assert_equal "\x89PNG".b, DesignPreview.call(@design).byteslice(0, 4)
  end

  # Transparency is what the workshop will not print. Shown as paper, not as the
  # browser's checkerboard.
  test "the preview is flattened onto white and capped in width" do
    attach(svg, "design.svg", "image/svg+xml")

    image = Vips::Image.new_from_buffer(DesignPreview.call(@design), "")

    assert_equal DesignPreview::WIDTH_PX, image.width
    assert_not image.has_alpha?
  end

  # The guard has to live here, not only where the file was stored: a guard that
  # depends on another class having done its job stops working the day a file
  # arrives by another route.
  test "an svg that would reach out of the document is never rendered" do
    attach(%(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">) +
           %(<style>@import url("https://ailleurs.example/x.css");</style></svg>),
           "design.svg", "image/svg+xml")

    assert_nil DesignPreview.call(@design)
  end

  test "an svg carrying a script is never rendered" do
    attach(%(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10">) +
           %(<script>fetch("https://ailleurs.example")</script></svg>),
           "design.svg", "image/svg+xml")

    assert_nil DesignPreview.call(@design)
  end

  private
    def attach(bytes, name, type)
      @design.print_file.attach(io: StringIO.new(bytes), filename: name, content_type: type)
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end

    def png
      Base64.decode64(
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
      )
    end
end
