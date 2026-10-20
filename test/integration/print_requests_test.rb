require "test_helper"

class PrintRequestsTest < ActionDispatch::IntegrationTest
  setup { attach_print_file }

  # Asked on 17/10/2026: the shop had to scroll past the sheet to find who to call.
  test "the workshop's request page shows the client's contact first" do
    sign_in_as users(:printer)
    print_requests(:waiting).update_columns(contact_phone: "+33612345678")

    get workshop_print_request_path(print_requests(:waiting))

    assert_response :success
    assert_select "#client_contact a[href='tel:+33612345678']"
    assert_operator response.body.index('id="client_contact"'), :<, response.body.index(I18n.t("workshop.print_requests.show.sheet"))
  end

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
    assert_equal printers(:rennes).id, request.printer_id
    assert_equal users(:client).id, request.client_id
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

  # C8, decided on 15/10/2026: the workshop is told by email.
  test "a cancelled request is announced to the workshop, and its page says who cancelled" do
    request = print_requests(:waiting)
    sign_in_as users(:client)

    assert_enqueued_email_with PrintRequestMailer, :canceled_to_printer, args: [ request ] do
      post cancel_print_request_path(request)
    end

    mail = PrintRequestMailer.canceled_to_printer(request.reload)
    assert_equal [ request.printer.orders_email ], mail.to
    assert_equal [ request.contact_email ], mail.reply_to

    sign_out
    get print_request_confirmation_path(request.confirmation_token)
    assert_select "p", text: I18n.t("print_requests.workshop_status_body.canceled")
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

  # Decided on 20/10/2026: the other answer to a request just received.
  test "a shop declines a request, the client is told, and it costs nothing within the share" do
    sign_in_as users(:printer)
    request = print_requests(:waiting)

    get workshop_print_request_path(request)
    assert_select "#decline button", text: I18n.t("workshop.print_requests.show.event.decline")

    assert_emails 1 do
      patch workshop_print_request_path(request), params: { event: "decline" }
      perform_enqueued_jobs
    end

    assert_predicate request.reload, :declined?
    assert_not_nil request.declined_at
    assert_includes ActionMailer::Base.deliveries.last.text_part.body.to_s,
                    I18n.t("print_requests.status_body.declined")
  end

  test "a request already taken on offers no way to decline it" do
    sign_in_as users(:printer)
    request = print_requests(:waiting)
    request.acknowledge!
    request.save!

    get workshop_print_request_path(request)
    assert_select "#decline", count: 0

    patch workshop_print_request_path(request), params: { event: "decline" }
    assert_predicate request.reload, :acknowledged?
  end

  test "the workshop's list has a tab for the requests it did not keep" do
    sign_in_as users(:printer)
    print_requests(:waiting).tap(&:decline!).save!

    get workshop_print_requests_path(statut: "declined")

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(print_requests(:waiting).token.first(8).upcase)}/
  end

  test "the confirmation that uses up the month's allowance tells the shop" do
    sign_in_as users(:printer)
    rennes = printers(:rennes)
    filler = Array.new(PrinterRequestQuota.for(rennes).remaining - 1) do
      copy = print_requests(:waiting).dup
      copy.assign_attributes(status: "acknowledged", sent_at: Time.current,
                             token: PrintRequest.generate_unique_secure_token,
                             confirmation_token: PrintRequest.generate_unique_secure_token)
      copy.save!(validate: false)
    end
    assert filler.all?

    assert_enqueued_email_with SubscriptionMailer, :request_quota_reached, args: [ rennes ] do
      patch workshop_print_request_path(print_requests(:waiting)), params: { event: "acknowledge" }
    end
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

  # --- Retrait ou livraison, express (decided on 16/10/2026) -------------

  test "the form offers the shop's ways back, the shipping cost and express" do
    printers(:rennes).update!(ships: true, shipping_price_note: "8 € par colis",
                              express_available: true, express_lead_hours: 48)
    sign_in_as users(:client)

    get new_design_print_request_path(designs(:fox_screen), atelier: printers(:rennes).slug)

    assert_select "input[name='print_request[delivery_method]'][value=pickup]"
    assert_select "input[name='print_request[delivery_method]'][value=shipping]"
    assert_match "L&#39;atelier vous contactera pour prendre vos coordonnées de livraison", response.body
    assert_match "Frais d&#39;envoi en supplément : 8 € par colis", response.body
    assert_match "Réalisée sous 48 heures", response.body
  end

  test "the chosen way and express reach the workshop's email" do
    printers(:rennes).update!(ships: true, express_available: true, express_lead_hours: 48)
    sign_in_as users(:client)

    assert_emails 2 do
      post design_print_requests_path(designs(:fox_screen), atelier: printers(:rennes).slug),
           params: { print_request: valid_params.merge(delivery_method: "shipping", express: "1") }
    end

    request = PrintRequest.order(:created_at).last
    assert_equal "shipping", request.delivery_method
    assert_predicate request, :express?

    workshop_email = ActionMailer::Base.deliveries.find { |m| m.to.include?(printers(:rennes).orders_email) }
    body = workshop_email.text_part.body.to_s
    assert_match "Livraison", body
    assert_match "frais d'envoi en supplément", body
    assert_match "Oui, sous 48 heures", body
  end

  test "a shop doing both ways makes the client choose" do
    printers(:rennes).update!(ships: true)
    sign_in_as users(:client)

    assert_no_difference "PrintRequest.count" do
      post design_print_requests_path(designs(:fox_screen), atelier: printers(:rennes).slug),
           params: { print_request: valid_params }
    end
    assert_response :unprocessable_entity
    assert_match "choisissez le retrait", response.body
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
        contact_name: "Claire Martin", contact_phone: "0612345678", contact_email: "claire@example.invalid",
        consent: "1"
      }
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end
end
