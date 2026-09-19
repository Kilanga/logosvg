require "application_system_test_case"

class PrintRequestsTest < ApplicationSystemTestCase
  setup do
    designs(:fox_screen).print_file.attach(
      io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
    )
  end

  # The completion criterion for step 4: the workshop confirms from its email,
  # and the client sees the status change.
  test "a client sends a design and the workshop confirms from its email" do
    sign_in users(:client)
    visit design_path(designs(:fox_screen))

    # One click from the design to a complete brief.
    click_on I18n.t("client.designs.show.send_to")

    assert_selector "h1", text: shown(printers(:rennes).name)

    choose "print_request_textile_source_printer", allow_label_click: true
    fill_in "print_request_textile_model", with: "Stanley Stella Creator"
    fill_in "print_request_textile_color", with: "Noir"
    check "placement_chest_center"

    fill_in "size_M", with: "12"
    fill_in "size_L", with: "8"

    # The run adds itself up where the decision is made.
    assert_selector "[data-size-run-target='output']", text: "20"

    check "print_request_consent"
    click_on I18n.t("client.print_requests.new.submit")

    assert_text displayed("enums.print_request.status.sent")

    request = PrintRequest.order(:created_at).last

    assert_equal 20, request.total_qty
    assert_equal [ "chest_center" ], request.placements
    assert_predicate request.final_file, :attached?

    # --- The workshop's side, from the link in its email -------------------
    sign_out
    visit print_request_confirmation_path(request.confirmation_token)

    assert_text displayed("public.print_request_confirmations.show.heading")

    click_on I18n.t("public.print_request_confirmations.show.confirm")

    assert_text displayed("public.print_request_confirmations.show.already_heading")
    assert_predicate request.reload, :acknowledged?

    # --- And the client sees it ---------------------------------------------
    sign_in users(:client)
    visit print_request_path(request)

    assert_text displayed("enums.print_request.status.acknowledged")
  end

  test "a workshop walks a request through its own screens" do
    sign_in users(:printer)
    visit workshop_print_requests_path

    assert_text shown(print_requests(:waiting).token.first(8).upcase)

    click_on I18n.t("workshop.print_requests.index.filter.open"), match: :first
    find("a[href='#{workshop_print_request_path(print_requests(:waiting))}']").click

    # One button: the next step, and only if it is possible from here.
    click_on I18n.t("workshop.print_requests.show.event.acknowledge")

    assert_text displayed("enums.print_request.status.acknowledged")

    click_on I18n.t("workshop.print_requests.show.event.quote")

    assert_text displayed("enums.print_request.status.quoted")
    assert_predicate print_requests(:waiting).reload, :quoted?
  end

  # The empty state is drawn, not left to the browser.
  test "a workshop with no request sees a drawn empty state" do
    sign_in users(:printer_lyon)
    print_requests(:acknowledged).destroy

    visit workshop_print_requests_path

    assert_text displayed("workshop.print_requests.index.empty.open")
    assert_text displayed("workshop.print_requests.index.empty_body")
  end

  test "a client calls a request off before the workshop begins" do
    sign_in users(:client)
    visit print_request_path(print_requests(:waiting))

    accept_confirm { click_on I18n.t("client.print_requests.show.cancel") }

    assert_text displayed("enums.print_request.status.canceled")
    assert_predicate print_requests(:waiting).reload, :canceled?
  end

  private
    def sign_in(user)
      visit new_session_path
      fill_in I18n.t("activerecord.attributes.user.email_address"), with: user.email_address
      fill_in I18n.t("activerecord.attributes.user.password"), with: "motdepasse-test"
      click_on I18n.t("sessions.new.submit")

      assert_no_current_path new_session_path
    end

    # The sign-out button lives in the space sidebar, not in the public header,
    # so this is called from a page inside a space.
    def sign_out
      click_on I18n.t("nav.sign_out")
      assert_text displayed("nav.sign_in")
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="200" height="200" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end
end
