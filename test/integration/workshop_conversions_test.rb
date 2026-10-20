require "test_helper"

# Asked for on 15/10/2026: the workshop puts one of its own pictures in its
# machine's format, and downloads the print file itself.
class WorkshopConversionsTest < ActionDispatch::IntegrationTest
  test "the workshop space offers the converter" do
    sign_in_as users(:printer)

    get workshop_dashboard_path
    assert_select "a[href=?]", workshop_conversions_path

    get new_workshop_conversion_path
    assert_response :success
    assert_select "input[type=file][name=?]", "design[reference_image]"
    assert_select "input[type=radio][value=?]", "screen_printing"
    assert_select "input[type=radio][value=?]", "dtf", count: 0
  end

  test "a picture becomes one of the workshop's designs, counted nowhere, and goes to the conversion" do
    sign_in_as users(:printer)

    assert_difference "Design.count", 1 do
      assert_no_difference -> { PrinterRequestQuota.new(printers(:rennes)).used } do
        assert_enqueued_with(job: GenerateDesignJob) do
          post workshop_conversions_path, params: { design: valid_conversion }
        end
      end
    end

    design = Design.order(:id).last
    assert_redirected_to workshop_conversion_path(design)
    assert_equal "upload", design.mode
    assert_equal users(:printer).id, design.user_id
    assert_equal printers(:rennes).id, design.printer_id
    assert_predicate design.reference_image, :attached?
  end

  test "only the shop's own techniques are converted to" do
    sign_in_as users(:printer)

    assert_no_difference "Design.count" do
      post workshop_conversions_path, params: { design: valid_conversion.merge(technique: "dtf") }
    end
    assert_response :unprocessable_entity
  end

  test "without a picture, or without the rights, nothing is created" do
    sign_in_as users(:printer)

    assert_no_difference "Design.count" do
      post workshop_conversions_path, params: { design: valid_conversion.except(:reference_image) }
      post workshop_conversions_path, params: { design: valid_conversion.merge(reference_rights_confirmed: "0") }
    end
  end

  test "the workshop downloads the print file itself, without a watermark" do
    design = conversion(users(:printer), printers(:rennes))
    sign_in_as users(:printer)

    get workshop_conversion_path(design)
    assert_select "a[href=?]", workshop_conversion_file_path(design)

    get workshop_conversion_file_path(design)
    assert_response :success
    assert_equal "image/svg+xml", response.media_type
    assert_match(/attachment; filename="logo-du-club\.svg"/, response.headers["Content-Disposition"])
    assert_equal svg, response.body
  end

  test "another workshop sees none of it" do
    design = conversion(users(:printer), printers(:rennes))
    sign_in_as users(:printer_lyon)

    get workshop_conversions_path
    assert_select "a[href=?]", workshop_conversion_path(design), count: 0

    get workshop_conversion_file_path(design)
    assert_response :not_found
  end

  # A client's own upload is never handed back as a print file, even by
  # this route: the client space and this one are not the same door.
  test "a client never reaches the converter, nor a print file through it" do
    design = conversion(users(:client), nil)
    sign_in_as users(:client)

    get new_workshop_conversion_path
    assert_response :redirect

    get workshop_conversion_file_path(design)
    assert_response :redirect
  end

  test "a conversion still running refreshes itself and offers no file" do
    design = conversion(users(:printer), printers(:rennes), status: "generating")
    sign_in_as users(:printer)

    get workshop_conversion_path(design)

    assert_select "meta[http-equiv=refresh]"
    assert_select "a[href=?]", workshop_conversion_file_path(design), count: 0
  end

  test "a conversion is removed from the list" do
    design = conversion(users(:printer), printers(:rennes))
    sign_in_as users(:printer)

    delete workshop_conversion_path(design)

    assert_redirected_to workshop_conversions_path
    assert_not_predicate design.reload, :active?
  end

  private
    def valid_conversion
      { prompt: "Logo du club", technique: "screen_printing", colors_requested: 3, remove_background: "1",
        reference_rights_confirmed: "1", ai_declared: "0",
        reference_image: Rack::Test::UploadedFile.new(StringIO.new(png), "image/png", original_filename: "logo.png") }
    end

    def conversion(user, printer, status: "ready")
      design = Design.new(user: user, printer: printer, mode: "upload", prompt: "Logo du club",
                          technique: "screen_printing", colors_requested: 3, print_width_cm: 25,
                          reference_rights_confirmed: true, status: status)
      design.reference_image.attach(io: StringIO.new(png), filename: "image-de-depart.png", content_type: "image/png")
      design.print_file.attach(io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml") if status == "ready"
      design.save!
      design
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="10" height="10"><rect width="10" height="10" fill="#000"/></svg>)
    end

    def png
      Vips::Image.black(300, 200).add(200).cast(:uchar).bandjoin([ 30, 40 ])
                 .copy(interpretation: :srgb).write_to_buffer(".png")
    end
end
