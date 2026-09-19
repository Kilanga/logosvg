require "test_helper"

class PrintRequestsTest < ActionDispatch::IntegrationTest
  setup { attach_print_file }

  # --- Sending -------------------------------------------------------------

  test "a client sends a finished design to a compatible shop" do
    sign_in_as users(:client)

    assert_difference "PrintRequest.count", 1 do
      assert_emails 2 do
        post design_print_requests_path(designs(:fox_screen), atelier: printers(:rennes).slug),
             params: { print_request: valid_params }
      end
    end

    request = PrintRequest.order(:created_at).last

    assert_redirected_to print_request_path(request)
    assert_predicate request, :sent?
    assert_equal printers(:rennes), request.printer
    assert_equal users(:client), request.client
    assert_equal 20, request.total_qty
  end

  # The consent is what lets the client's details reach the workshop at all.
  test "a request without consent does not leave" do
    sign_in_as users(:client)

    assert_no_difference "PrintRequest.count" do
      post design_print_requests_path(designs(:fox_screen), atelier: printers(:rennes).slug),
           params: { print_request: valid_params.except(:consent) }
    end

    assert_response :unprocessable_entity
  end

  test "the consent is recorded with the version of the text that was shown" do
    sign_in_as users(:client)

    post design_print_requests_path(designs(:fox_screen), atelier: printers(:rennes).slug),
         params: { print_request: valid_params }

    request = PrintRequest.order(:created_at).last

    assert_equal Rails.application.config.tshirt.privacy[:consent_text_version],
                 request.consent_text_version
    assert_not_nil request.consented_at
  end

  # The directory says so on screen; the server says so too.
  test "a shop that does not practise the technique is refused the job" do
    sign_in_as users(:client)

    assert_no_difference "PrintRequest.count" do
      assert_no_emails do
        post design_print_requests_path(designs(:fox_screen), atelier: printers(:lyon).slug),
             params: { print_request: valid_params }
      end
    end

    assert_response :unprocessable_entity
  end

  test "a run under the shop's minimum comes back with the form" do
    sign_in_as users(:client)

    post design_print_requests_path(designs(:fox_screen), atelier: printers(:rennes).slug),
         params: { print_request: valid_params.merge(sizes: { "M" => "2" }) }

    assert_response :unprocessable_entity
  end

  test "a client never sends someone else's design" do
    sign_in_as users(:client)

    get new_design_print_request_path(designs(:other_client_design))

    assert_response :not_found
  end

  test "only a client sends" do
    [ :printer, :designer, :admin ].each do |role|
      sign_in_as users(role)
      get new_design_print_request_path(designs(:fox_screen))

      assert_response :redirect, "#{role} must not reach the sending form"

      sign_out
    end
  end

  # --- Following -----------------------------------------------------------

  test "a client reads their own request and nobody else's" do
    sign_in_as users(:client)

    get print_request_path(print_requests(:waiting))

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(printers(:rennes).name)}/i
  end

  test "a client cancels while the shop has not begun" do
    sign_in_as users(:client)

    post cancel_print_request_path(print_requests(:waiting))

    assert_predicate print_requests(:waiting).reload, :canceled?
  end

  # --- The workshop's confirmation page ------------------------------------

  # Mail scanners follow links on their own: opening the page must change
  # nothing at all.
  test "opening the confirmation link does not acknowledge anything" do
    get print_request_confirmation_path(print_requests(:waiting).confirmation_token)

    assert_response :success
    assert_predicate print_requests(:waiting).reload, :sent?
  end

  test "the button on that page acknowledges, and tells the client" do
    assert_emails 1 do
      post print_request_confirmation_path(print_requests(:waiting).confirmation_token)
      perform_enqueued_jobs
    end

    assert_predicate print_requests(:waiting).reload, :acknowledged?
  end

  # The workshop opens this from its inbox. Nothing on it may require signing
  # in — the token is the authorization.
  test "the confirmation page needs no account at all" do
    assert_nil cookies["session_id"].presence

    get print_request_confirmation_path(print_requests(:waiting).confirmation_token)

    assert_response :success
    assert_select "form[action=?]",
                  print_request_confirmation_path(print_requests(:waiting).confirmation_token)
    assert_select "button", text: I18n.t("public.print_request_confirmations.show.confirm")
  end

  test "a token that matches nothing is not found" do
    get print_request_confirmation_path("pas-un-jeton")

    assert_response :not_found
  end

  test "a request already acknowledged cannot be acknowledged again" do
    token = print_requests(:acknowledged).confirmation_token

    assert_no_emails do
      post print_request_confirmation_path(token)
      perform_enqueued_jobs
    end

    assert_response :unprocessable_entity
  end

  test "a canceled request leaves a dead link" do
    print_requests(:waiting).cancel!

    post print_request_confirmation_path(print_requests(:waiting).confirmation_token)

    assert_response :unprocessable_entity
    assert_predicate print_requests(:waiting).reload, :canceled?
  end

  # --- The workshop's own screens ------------------------------------------

  test "a shop sees the requests it received, and no others" do
    sign_in_as users(:printer)

    get workshop_print_requests_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(print_requests(:waiting).token.first(8).upcase)}/
    assert_select "body", text: /#{Regexp.escape(print_requests(:acknowledged).token.first(8).upcase)}/, count: 0
  end

  test "a shop moves a request along and the client is told" do
    sign_in_as users(:printer)

    assert_emails 1 do
      patch workshop_print_request_path(print_requests(:waiting)), params: { event: "acknowledge" }
      perform_enqueued_jobs
    end

    assert_predicate print_requests(:waiting).reload, :acknowledged?
  end

  test "a shop cannot skip a step" do
    sign_in_as users(:printer)

    patch workshop_print_request_path(print_requests(:waiting)), params: { event: "complete" }

    assert_predicate print_requests(:waiting).reload, :sent?
  end

  # `cancel` is the client's; a workshop must not reach it through this action.
  test "a shop cannot cancel on the client's behalf" do
    sign_in_as users(:printer)

    patch workshop_print_request_path(print_requests(:waiting)), params: { event: "cancel" }

    assert_predicate print_requests(:waiting).reload, :sent?
  end

  test "a shop never reaches another shop's request" do
    sign_in_as users(:printer_lyon)

    patch workshop_print_request_path(print_requests(:waiting)), params: { event: "acknowledge" }

    assert_response :not_found
    assert_predicate print_requests(:waiting).reload, :sent?
  end

  private
    def attach_print_file
      designs(:fox_screen).print_file.attach(
        io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
      )
    end

    def valid_params
      {
        textile_source: "printer", textile_model: "Stanley Stella", textile_color: "Noir",
        placements: [ "chest_center" ], sizes: { "M" => "12", "L" => "8" },
        contact_name: "Claire Martin", contact_email: "claire@example.invalid",
        consent: "1"
      }
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end
end
