require "test_helper"

# The workshop's converter offered to designers, only inside a client's review
# (asked for on 17/10/2026).
class ReviewConversionsTest < ActionDispatch::IntegrationTest
  test "the designer at work on a review sees the converter" do
    sign_in_as users(:designer)

    get designer_review_path(reviews(:in_progress_vector))

    assert_select "section#conversions form[action=?]",
                  designer_review_conversions_path(reviews(:in_progress_vector))
  end

  test "a conversion takes the review's technique and is drawn in the background" do
    review = reviews(:in_progress_vector)
    sign_in_as users(:designer)

    assert_enqueued_with(job: GenerateDesignJob) do
      assert_difference -> { Design.count }, 1 do
        post designer_review_conversions_path(review), params: { image: uploaded_png, remove_background: "1" }
      end
    end

    design = Design.strict_loading(false).order(:id).last

    assert_redirected_to designer_review_path(review, anchor: "conversions")
    assert_equal review.id, design.conversion_review_id
    assert_equal users(:designer), design.user
    assert_equal "upload", design.mode
    assert_equal review.design.technique, design.technique
    assert_equal review.design.colors_requested, design.colors_requested
    assert design.remove_background
    assert_predicate design.reference_image, :attached?
  end

  test "no image, no conversion" do
    sign_in_as users(:designer)

    assert_no_difference -> { Design.count } do
      post designer_review_conversions_path(reviews(:in_progress_vector))
    end

    assert_equal I18n.t("designer.review_conversions.create.missing_image"), flash[:alert]
  end

  test "another designer cannot convert inside someone else's review" do
    sign_in_as users(:designer_maya)

    assert_no_difference -> { Design.count } do
      post designer_review_conversions_path(reviews(:in_progress_vector)), params: { image: uploaded_png }
    end
  end

  test "a review not yet claimed offers no converter" do
    sign_in_as users(:designer)

    assert_no_difference -> { Design.count } do
      post designer_review_conversions_path(reviews(:queued)), params: { image: uploaded_png }
    end
  end

  test "the converted file downloads once it is ready, and only for its designer" do
    review = reviews(:in_progress_vector)
    design = conversion_for(review)
    sign_in_as users(:designer)

    get designer_review_conversion_file_path(review, design_token: design.token)

    assert_response :not_found

    design.update!(status: "ready")
    design.print_file.attach(io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml")

    get designer_review_conversion_file_path(review, design_token: design.token)

    assert_response :success
    assert_equal "image/svg+xml", response.media_type
    assert_includes response.headers["Content-Disposition"], "converti.svg"

    get designer_review_path(review)

    assert_select "a[href=?]", designer_review_conversion_file_path(review, design_token: design.token)
  end

  test "a design that names no review cannot be fetched through one" do
    review = reviews(:in_progress_vector)
    sign_in_as users(:designer)

    get designer_review_conversion_file_path(review, design_token: designs(:fox_screen).token)

    assert_response :not_found
  end

  private
    def conversion_for(review)
      design = Design.new(user: users(:designer), printer: review.design.printer, conversion_review: review,
                          mode: "upload", style: "illustration", prompt: "Conversion", status: "pending",
                          technique: review.design.technique, colors_requested: review.design.colors_requested,
                          print_width_cm: review.design.print_width_cm, reference_rights_confirmed: true)
      design.reference_image.attach(io: StringIO.new(uploaded_png.read), filename: "retouche.png",
                                    content_type: "image/png")
      design.tap(&:save!)
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="#000"/></svg>)
    end

    def uploaded_png
      png = Vips::Image.black(300, 200).add(200).cast(:uchar).bandjoin([ 30, 40 ])
                       .copy(interpretation: :srgb).write_to_buffer(".png")
      Rack::Test::UploadedFile.new(StringIO.new(png), "image/png", original_filename: "retouche.png")
    end
end
