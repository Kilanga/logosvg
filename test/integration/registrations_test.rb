require "test_helper"

class RegistrationsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  test "the form is open to a visitor" do
    get new_registration_path

    assert_response :success
  end

  test "the role from the link is preselected" do
    get new_registration_path(role: "printer")

    assert_response :success
    assert_select "input[name=?][value=?][checked]", "user[role]", "printer"
  end

  test "a visitor signs up and lands in the space of the role they chose" do
    assert_difference "User.count", 1 do
      post registration_path, params: valid_params(role: "printer")
    end

    user = User.order(:created_at).last

    assert_predicate user, :printer?
    assert_not_nil user.terms_accepted_at
    assert_redirected_to "/atelier"
  end

  test "signing up opens a session straight away" do
    post registration_path, params: valid_params(role: "designer")

    follow_redirect!

    assert_response :success
  end

  test "an unknown role is refused rather than turned into another one" do
    assert_no_difference "User.count" do
      post registration_path, params: valid_params(role: "sorcier")
    end

    assert_response :unprocessable_entity
  end

  test "nobody signs up as an administrator" do
    assert_no_difference "User.count" do
      post registration_path, params: valid_params(role: "admin")
    end

    assert_response :unprocessable_entity
    assert_empty User.admin.where.not(id: users(:admin).id)
  end

  test "terms left unchecked stop the account being created" do
    assert_no_difference "User.count" do
      post registration_path, params: valid_params(role: "printer").tap { |p| p[:user].delete(:terms) }
    end

    assert_response :unprocessable_entity
  end

  test "an address already registered stops the account being created" do
    assert_no_difference "User.count" do
      post registration_path, params: valid_params(role: "printer", email_address: users(:client).email_address)
    end

    assert_response :unprocessable_entity
  end

  test "someone already signed in is refused the form" do
    sign_in_as users(:client)

    get new_registration_path

    assert_redirected_to "/mon-espace"
  end

  # --- A client account comes through a workshop (09/10/2026) ---------------

  test "without a workshop, the client role is not offered and the form says where to go" do
    get new_registration_path

    assert_select "input[name=?][value=?]", "user[role]", "client", count: 0
    assert_select "a[href=?]", printers_path
  end

  test "without a workshop, a client account is refused" do
    assert_no_difference "User.count" do
      post registration_path, params: valid_params
    end

    assert_response :unprocessable_entity
    assert_match "lien de votre atelier", response.body
  end

  test "the shop's code admits the new client at once" do
    printer = printers(:rennes)
    get workshop_invite_path(slug: printer.slug, code: printer.invite_code)
    get new_registration_path

    assert_select "input[name=?][value=?][checked]", "user[role]", "client"

    assert_no_enqueued_emails do
      post registration_path, params: valid_params
    end

    user = User.find_by!(email_address: "nouvelle@example.invalid")
    assert_equal printer.id, user.workshop_id
    assert ClientAffiliation.accepted.from_invitation.exists?(client: user, printer: printer)
    assert_redirected_to "/mon-espace"
  end

  test "a shop's page without its code makes the account a request the shop must answer" do
    printer = printers(:lyon)
    get workshop_link_path(slug: printer.slug)

    assert_enqueued_email_with AffiliationMailer, :requested, args: ->(args) { args.first.is_a?(ClientAffiliation) } do
      post registration_path, params: valid_params
    end

    user = User.find_by!(email_address: "nouvelle@example.invalid")
    assert_nil user.workshop_id
    assert ClientAffiliation.pending.from_request.exists?(client: user, printer: printer)
  end

  test "a wrong code is only a request" do
    printer = printers(:rennes)
    get workshop_invite_path(slug: printer.slug, code: "pas-le-bon")
    post registration_path, params: valid_params

    user = User.find_by!(email_address: "nouvelle@example.invalid")
    assert_nil user.workshop_id
    assert ClientAffiliation.pending.exists?(client: user, printer: printer)
  end

  private
    def valid_params(**overrides)
      {
        user: {
          email_address: "nouvelle@example.invalid",
          password: "motdepasse-test",
          password_confirmation: "motdepasse-test",
          first_name: "Nouvelle",
          last_name: "Personne",
          city: "Brest",
          role: "client",
          terms: "1"
        }.merge(overrides)
      }
    end
end
