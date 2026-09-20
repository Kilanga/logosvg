require "test_helper"

# The completion criterion for step 5: every list is held to the signed-in
# client, and no list issues one query per row.
class ClientSpaceTest < ActionDispatch::IntegrationTest
  setup do
    designs(:fox_screen).print_file.attach(
      io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
    )
    designs(:fox_dtf).print_file.attach(
      io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
    )
  end

  # --- Who sees what -------------------------------------------------------

  test "every screen of the space is closed to the other roles" do
    paths = [ client_dashboard_path, client_designs_path, client_print_requests_path,
              client_reviews_path, client_account_path ]

    [ :printer, :designer, :admin ].each do |role|
      sign_in_as users(role)

      paths.each do |path|
        get path

        assert_response :redirect, "#{role} must not reach #{path}"
      end

      sign_out
    end
  end

  test "a visitor is sent to sign in rather than to a list" do
    get client_designs_path

    assert_redirected_to new_session_path
  end

  # --- The lists -----------------------------------------------------------

  test "the design list shows one card per lineage, not one per variant" do
    variant = CreateDesignChildren.call(parent: designs(:fox_screen)) { { "job_id" => "v1" } }.first
    sign_in_as users(:client)

    get client_designs_path

    assert_response :success
    assert_select "a[href=?]", design_path(designs(:fox_screen))
    assert_select "li.panel", count: Design.active.roots.where(user: users(:client)).count
    assert_equal designs(:fox_screen), variant.root
  end

  test "the design list holds to the signed-in client" do
    sign_in_as users(:client)

    get client_designs_path

    assert_select "a[href=?]", design_path(designs(:other_client_design)), count: 0
  end

  test "a soft-deleted design is gone from the list" do
    designs(:fox_dtf).soft_delete!
    sign_in_as users(:client)

    get client_designs_path

    assert_select "a[href=?]", design_path(designs(:fox_dtf)), count: 0
  end

  test "the print request list holds to the signed-in client" do
    sign_in_as users(:client)

    get client_print_requests_path

    assert_response :success
    assert_select "a[href=?]", print_request_path(print_requests(:waiting))
  end

  test "a printer's own requests never appear in a client's list" do
    sign_in_as users(:printer)

    get client_print_requests_path

    assert_response :redirect, "a printer has no client space"
  end

  test "the reviews list holds to the signed-in client" do
    sign_in_as users(:client)

    get client_reviews_path

    assert_response :success
    assert_select "a[href=?]", review_path(reviews(:delivered))
  end

  test "a client with no review sees a drawn empty state" do
    users(:deleted_client).update!(deleted_at: nil)
    sign_in_as users(:deleted_client)

    get client_reviews_path

    assert_select "body", text: /#{Regexp.escape(I18n.t('client.reviews.index.empty'))}/i
  end

  # Aucune requête N+1 sur les listes.
  test "the design list does not issue one query per design" do
    sign_in_as users(:client)
    get client_designs_path

    counted = count_queries { get client_designs_path }

    assert_operator counted, :<, 25, "#{counted} queries for a handful of designs"
  end

  test "the print request list does not issue one query per request" do
    sign_in_as users(:client)
    get client_print_requests_path

    counted = count_queries { get client_print_requests_path }

    assert_operator counted, :<, 25, "#{counted} queries for a handful of requests"
  end

  # --- The dashboard -------------------------------------------------------

  test "the dashboard leads with what is waiting on the client" do
    sign_in_as users(:client)

    get client_dashboard_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(I18n.t('client.dashboards.show.waiting_on_you'))}/i
  end

  # --- Deleting a design ---------------------------------------------------

  test "a client deletes their own design, and it is only soft-deleted" do
    sign_in_as users(:client)

    assert_no_difference "Design.count" do
      delete delete_design_path(designs(:fox_dtf))
    end

    assert_redirected_to client_designs_path
    assert_not_predicate designs(:fox_dtf).reload, :active?
  end

  # The workshop's copy of the files is its own; deleting the design must not
  # reach into a job already sent.
  test "deleting a design leaves a sent print request untouched" do
    sign_in_as users(:client)

    delete delete_design_path(designs(:fox_screen))

    assert_predicate print_requests(:waiting).reload, :sent?
  end

  test "a client never deletes someone else's design" do
    sign_in_as users(:client)

    delete delete_design_path(designs(:other_client_design))

    assert_response :not_found
    assert_predicate designs(:other_client_design).reload, :active?
  end

  # --- The account ---------------------------------------------------------

  test "a client updates their own details" do
    sign_in_as users(:client)

    patch client_account_path, params: { user: { first_name: "Claire-Marie", city: "Rennes" } }

    assert_redirected_to client_account_path
    assert_equal "Claire-Marie", users(:client).reload.first_name
    assert_equal "Rennes", users(:client).city
  end

  # The address identifies the account: it is not a field on this form.
  test "the email address cannot be changed from the details form" do
    sign_in_as users(:client)
    before = users(:client).email_address

    patch client_account_path, params: { user: { email_address: "autre@example.invalid" } }

    assert_equal before, users(:client).reload.email_address
  end

  test "neither can the role" do
    sign_in_as users(:client)

    patch client_account_path, params: { user: { role: "admin" } }

    assert_predicate users(:client).reload, :client?
  end

  test "an invalid change comes back with the form" do
    sign_in_as users(:client)

    patch client_account_path, params: { user: { first_name: "" } }

    assert_response :unprocessable_entity
    assert_equal "Claire", users(:client).reload.first_name
  end

  # --- The password --------------------------------------------------------

  test "a client changes their password with the current one in hand" do
    sign_in_as users(:client)

    patch client_account_password_path, params: {
      user: { current_password: "motdepasse-test",
              password: "un-nouveau-mot-de-passe", password_confirmation: "un-nouveau-mot-de-passe" }
    }

    assert_redirected_to client_account_path
    assert users(:client).reload.authenticate("un-nouveau-mot-de-passe")
  end

  # The case this guards: a browser left open and unattended.
  test "a wrong current password changes nothing" do
    sign_in_as users(:client)

    patch client_account_password_path, params: {
      user: { current_password: "pas-le-bon",
              password: "un-nouveau-mot-de-passe", password_confirmation: "un-nouveau-mot-de-passe" }
    }

    assert_response :unprocessable_entity
    assert users(:client).reload.authenticate("motdepasse-test")
  end

  test "a confirmation that does not match changes nothing" do
    sign_in_as users(:client)

    patch client_account_password_path, params: {
      user: { current_password: "motdepasse-test",
              password: "un-nouveau-mot-de-passe", password_confirmation: "autre-chose" }
    }

    assert_response :unprocessable_entity
    assert users(:client).reload.authenticate("motdepasse-test")
  end

  # Changing a password is how someone locks out whoever they think is reading
  # their mail.
  test "changing the password drops every other session" do
    other = users(:client).sessions.create!
    sign_in_as users(:client)

    patch client_account_password_path, params: {
      user: { current_password: "motdepasse-test",
              password: "un-nouveau-mot-de-passe", password_confirmation: "un-nouveau-mot-de-passe" }
    }

    assert_not Session.exists?(other.id)
    assert Session.exists?(Current.session.id), "the session doing the changing survives"
  end

  private
    def count_queries
      count = 0
      counter = ->(_name, _start, _finish, _id, payload) do
        count += 1 unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ])
      end

      ActiveSupport::Notifications.subscribed(counter, "sql.active_record") { yield }
      count
    end

    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end
end
