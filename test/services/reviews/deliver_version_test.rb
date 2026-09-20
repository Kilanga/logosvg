require "test_helper"

module Reviews
  class DeliverVersionTest < ActiveSupport::TestCase
    test "a valid svg is stored, numbered, and moves the review along" do
      result = deliver(reviews(:in_progress_vector), svg_file)

      assert_predicate result, :success?
      assert_equal 1, result.version.number
      assert_predicate result.version.file, :attached?
      assert_predicate reviews(:in_progress_vector).reload, :delivered?
    end

    test "the inks the inspector counted are kept on the version" do
      result = deliver(reviews(:in_progress_vector), two_colour_svg)

      assert_equal 2, result.version.inks_count
      assert_equal 2, result.version.checks["inks"]
    end

    # A designer does not return a PNG where the workshop expects an SVG.
    test "a png offered where an svg is expected is refused" do
      result = deliver(reviews(:in_progress_vector), png_file)

      assert_not_predicate result, :success?
      assert_predicate reviews(:in_progress_vector).reload, :in_progress?
    end

    test "an svg offered where a png is expected is refused" do
      result = deliver(reviews(:in_progress), svg_file)

      assert_not_predicate result, :success?
    end

    # The whole reason SvgInspector exists, applied to a file a stranger sent.
    test "an svg carrying a script is refused" do
      dangerous = upload(%(<svg xmlns="http://www.w3.org/2000/svg"><script>x()</script></svg>),
                         "image/svg+xml", "version.svg")

      result = deliver(reviews(:in_progress_vector), dangerous)

      assert_not_predicate result, :success?
      assert_equal 0, reviews(:in_progress_vector).versions.count
    end

    test "a file that is not a png at all is refused, whatever it is named" do
      fake = upload("ceci n'est pas une image", "image/png", "version.png")

      result = deliver(reviews(:in_progress), fake)

      assert_not_predicate result, :success?
      assert_equal I18n.t("reviews.errors.raster.not_a_png"), result.error
    end

    test "nothing attached is refused before anything else happens" do
      result = deliver(reviews(:in_progress), nil)

      assert_not_predicate result, :success?
      assert_equal I18n.t("reviews.errors.no_file"), result.error
    end

    # A second version on a review already delivered is a delivery too, but
    # there is no state left to move.
    test "a second version is numbered after the first" do
      deliver(reviews(:in_progress_vector), svg_file)
      review = reviews(:in_progress_vector).reload
      review.request_revision!
      review.save!

      result = deliver(review, two_colour_svg)

      assert_equal 2, result.version.number
      assert_predicate review.reload, :delivered?
    end

    test "the client is told a version has arrived" do
      assert_emails 1 do
        deliver(reviews(:in_progress_vector), svg_file)
        perform_enqueued_jobs
      end
    end

    private
      def deliver(review, file, message: "Voici la reprise.")
        DeliverVersion.call(review: review, file: file, message: message)
      end

      def upload(content, type, name)
        Rack::Test::UploadedFile.new(StringIO.new(content), type, original_filename: name)
      end

      def svg_file
        upload(%(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">) +
               %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>), "image/svg+xml", "version.svg")
      end

      def two_colour_svg
        upload(%(<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">) +
               %(<path d="M0 0h5v10H0z" fill="#1F5F7A"/><path d="M5 0h5v10H5z" fill="#E4572E"/></svg>),
               "image/svg+xml", "version.svg")
      end

      def png_file
        upload(Base64.decode64(
          "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
        ), "image/png", "version.png")
      end
  end
end
