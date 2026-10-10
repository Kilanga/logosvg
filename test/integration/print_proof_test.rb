require "test_helper"

# Decided on 10/10/2026: a client's own picture is changed by the technique —
# flattened into a few inks, or kept whole at 300 dpi — so the client sees it
# beside the print rendering, reads what changed, and approves it before any
# workshop receives it. And may try the same picture with another technique.
class PrintProofTest < ActionDispatch::IntegrationTest
  setup do
    @design = ready_upload
    sign_in_as users(:client)
  end

  test "the proof shows the client's image beside the print rendering, and what changed" do
    get design_path(@design)

    assert_response :success
    assert_select "img[src=?]", design_reference_image_path(@design)
    assert_select "img[src=?]", design_garment_image_path(@design)
    assert_select "li", text: I18n.t("designs.changes.flattened", count: 2)
    assert_select "li", text: I18n.t("designs.changes.background_removed")
    assert_select "form[action=?] input[type=checkbox][name=confirmed][required]", design_print_approval_path(@design)
  end

  test "before approval, no workshop is offered and none can be reached" do
    get design_path(@design)
    assert_select "a[href^=?]", new_design_print_request_path(@design), count: 0
    assert_select "p", text: I18n.t("client.designs.show.approve_first").squish

    get new_design_print_request_path(@design)
    assert_redirected_to design_path(@design)

    assert_no_difference "PrintRequest.count" do
      post design_print_requests_path(@design), params: { print_request: request_params }
    end
    assert_redirected_to design_path(@design)
  end

  test "approving without ticking the box approves nothing" do
    post design_print_approval_path(@design)

    assert_redirected_to design_path(@design)
    assert_nil @design.reload.print_approved_at
  end

  test "once approved, the client goes straight on to the request, and it leaves" do
    post design_print_approval_path(@design), params: { confirmed: "1" }

    assert_redirected_to new_design_print_request_path(@design)
    assert_not_nil @design.reload.print_approved_at

    follow_redirect!
    assert_response :success

    assert_difference "PrintRequest.count", 1 do
      post design_print_requests_path(@design), params: { print_request: request_params }
    end
  end

  test "a proof is approved once, and only by its owner" do
    @design.approve_print!
    approved_at = @design.reload.print_approved_at
    post design_print_approval_path(@design), params: { confirmed: "1" }
    assert_response :redirect
    assert_equal approved_at, @design.reload.print_approved_at

    post design_print_approval_path(designs(:other_client_design)), params: { confirmed: "1" }
    assert_response :not_found
  end

  test "what the platform drew needs no proof" do
    assert_predicate designs(:fox_screen), :print_approved?
    get design_path(designs(:fox_screen))
    assert_select "form[action=?]", design_print_approval_path(designs(:fox_screen)), count: 0
  end

  test "the same picture is tried with another of the shop's techniques, without sending it again" do
    offer_dtf_at_rennes

    get new_design_upload_path(depuis: @design.token)
    assert_response :success
    assert_select "input[type=file]", count: 0
    assert_select "img[src=?]", design_reference_image_path(@design)
    assert_select "input[type=radio][value=dtf][checked]"

    assert_difference "Design.count", 1 do
      assert_enqueued_with(job: GenerateDesignJob) do
        post design_uploads_path(depuis: @design.token),
             params: { design: { prompt: @design.prompt, technique: "dtf", print_width_cm: 25, remove_background: "1" } }
      end
    end

    again = Design.order(:id).last
    assert_redirected_to design_path(again)
    assert_equal [ "upload", "dtf" ], [ again.mode, again.technique ]
    assert_equal @design.reference_image.download, again.reference_image.download
    assert_nil again.print_approved_at, "a new rendering is a new proof"
    assert_equal 0, GenerationQuota.for(users(:client)).used
  end

  test "another client's picture cannot be borrowed" do
    get new_design_upload_path(depuis: designs(:other_client_design).token)
    assert_response :not_found
  end

  private
    def ready_upload
      design = Design.new(user: users(:client), printer: printers(:rennes), mode: "upload", prompt: "Logo du club",
                          technique: "screen_printing", colors_requested: 2, print_width_cm: 25,
                          remove_background: true, reference_rights_confirmed: true)
      design.reference_image.attach(io: StringIO.new(png), filename: "image-de-depart.png", content_type: "image/png")
      design.save!
      design.print_file.attach(io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml")
      design.update_columns(status: "ready", print_format: "svg", inks_count: 2,
                            palette: [ { hex: "#1F5F7A" }, { hex: "#E4572E" } ], stats: { paths: 12 })
      design
    end

    def offer_dtf_at_rennes
      PrinterTechnique.create!(printer: printers(:rennes), technique: "dtf", output_format: "png",
                               color_space: "rgb", primary: false, max_print_width_cm: 40, max_print_height_cm: 50)
    end

    def request_params
      {
        textile_source: "printer", textile_model: "Stanley Stella", textile_color: "Noir",
        placements: [ "chest_center" ], sizes: { "M" => "12", "L" => "8" },
        contact_name: "Claire Martin", contact_email: "claire@example.invalid", consent: "1"
      }
    end

    def png
      Vips::Image.black(300, 200).add(200).cast(:uchar).bandjoin([ 30, 40 ])
                 .copy(interpretation: :srgb).write_to_buffer(".png")
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end
end
