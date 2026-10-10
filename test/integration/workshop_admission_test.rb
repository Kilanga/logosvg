require "test_helper"

# The poster admitting once, only the shop extending a client's thirty days
# (decided on 09/10/2026), and the way each client came in (decided on
# 10/10/2026): a client cannot keep the AI running without ever sending a
# design to a workshop, and the shop knows which of its supports work.
class WorkshopAdmissionTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @rennes = printers(:rennes)
    @lyon = printers(:lyon)
    @stranger = new_client("inconnu@example.invalid")
  end

  # --- The poster admits once ---------------------------------------------------

  test "the poster admits a client who has never been the shop's" do
    sign_in_as @stranger

    get workshop_invite_path(slug: @lyon.slug, code: @lyon.invite_code)
    follow_redirect!

    assert_redirected_to new_design_path
    assert_equal @lyon.id, @stranger.reload.active_workshop_id
  end

  test "a former client scanning the poster again is asked to make a request" do
    ClientAffiliation.admit!(client: @stranger, printer: @lyon)
    @stranger.update!(workshop_until: 1.minute.ago)
    sign_in_as @stranger

    get workshop_invite_path(slug: @lyon.slug, code: @lyon.invite_code)
    follow_redirect!

    assert_response :success
    assert_match "Son affiche admet d&#39;office les", response.body
    assert_not @stranger.reload.attached_to_workshop?

    post join_workshop_path(slug: @lyon.slug)
    assert ClientAffiliation.pending.exists?(client: @stranger, printer: @lyon)
  end

  # --- Where each client came from (decided on 10/10/2026) -----------------------

  test "the way in is kept on the client's row: the poster's QR code" do
    get workshop_invite_path(slug: @rennes.slug, code: @rennes.invite_code, s: "qr")
    post registration_path, params: signup("affiche@example.invalid")

    client = User.find_by!(email_address: "affiche@example.invalid")
    assert_equal @rennes.id, client.active_workshop_id
    assert_equal "qr", ClientAffiliation.accepted.find_by!(client: client).channel
  end

  test "the email the shop sent admits like the poster, and says so" do
    get workshop_invite_path(slug: @rennes.slug, code: @rennes.invite_code, s: "email")
    post registration_path, params: signup("par-email@example.invalid")

    client = User.find_by!(email_address: "par-email@example.invalid")
    assert_equal @rennes.id, client.active_workshop_id
    assert_equal "email", ClientAffiliation.accepted.find_by!(client: client).channel
  end

  test "a named link is kept by its key, and an unknown one as the plain link" do
    @rennes.link_channels.create!(label: "Flyer")

    get workshop_invite_path(slug: @rennes.slug, code: @rennes.invite_code, s: "flyer")
    post registration_path, params: signup("flyer@example.invalid")
    reset!
    get workshop_invite_path(slug: @rennes.slug, code: @rennes.invite_code, s: "nimporte-quoi")
    post registration_path, params: signup("autre@example.invalid")

    assert_equal "flyer", ClientAffiliation.find_by!(client: User.find_by!(email_address: "flyer@example.invalid")).channel
    assert_equal "link", ClientAffiliation.find_by!(client: User.find_by!(email_address: "autre@example.invalid")).channel
  end

  test "a code-less visit leaves no channel: the directory, decided by the shop" do
    get workshop_link_path(slug: @rennes.slug)
    post registration_path, params: signup("annuaire@example.invalid")

    affiliation = ClientAffiliation.find_by!(client: User.find_by!(email_address: "annuaire@example.invalid"))
    assert_predicate affiliation, :pending?
    assert_nil affiliation.channel
  end

  test "a former client's request says which support brought them back" do
    ClientAffiliation.admit!(client: @stranger, printer: @rennes)
    @stranger.update!(workshop_until: 1.minute.ago)
    sign_in_as @stranger

    get workshop_invite_path(slug: @rennes.slug, code: @rennes.invite_code, s: "qr")
    post join_workshop_path(slug: @rennes.slug)

    assert_equal "qr", ClientAffiliation.pending.find_by!(client: @stranger, printer: @rennes).channel

    sign_in_as users(:printer)
    get workshop_clients_path
    assert_select "li", text: /Paul Inconnu.*Ancien client, revenu par : QR code de l'affiche/m
  end

  test "the clients list says how each client came" do
    ClientAffiliation.admit!(client: @stranger, printer: @rennes, channel: "email")
    sign_in_as users(:printer)

    get workshop_clients_path

    assert_select "li", text: /Paul Inconnu.*arrivé par : Email envoyé/m
  end

  test "the withdrawn numbered sheets lead to the directory" do
    get "/f/ancienne-fiche"

    assert_redirected_to "/imprimeurs"
  end

  # --- Only the shop extends ------------------------------------------------------

  test "the shop confirming a print request gives the client thirty more days" do
    client = users(:client)
    client.update!(workshop_until: 2.days.from_now)
    request = print_requests(:waiting)

    request.acknowledge!

    assert_in_delta 30.days.from_now, client.reload.workshop_until, 1.minute
  end

  test "a confirmation by another shop does not move the client" do
    client = users(:client)
    client.update!(workshop_until: 2.days.from_now)

    User.extend_attachment!(client_id: client.id, printer_id: @lyon.id)

    assert_in_delta 2.days.from_now, client.reload.workshop_until, 1.minute
    assert_equal @rennes.id, client.workshop_id
  end

  test "the shop extends a client with « Prolonger »" do
    client = users(:client)
    client.update!(workshop_until: 2.days.from_now)
    sign_in_as users(:printer)

    post extend_workshop_client_path(client)

    assert_in_delta 30.days.from_now, client.reload.workshop_until, 1.minute
  end

  test "a shop cannot extend another shop's client" do
    sign_in_as users(:printer_lyon)

    post extend_workshop_client_path(users(:client))

    assert_response :not_found
  end

  private
    def new_client(email)
      User.create!(email_address: email, password: "motdepasse-test", first_name: "Paul",
                   last_name: "Inconnu", role: "client", terms_accepted_at: Time.current)
    end

    def signup(email)
      { user: { email_address: email, password: "motdepasse-test", password_confirmation: "motdepasse-test",
                first_name: "Nouvelle", last_name: "Personne", role: "client", terms: "1" } }
    end
end
