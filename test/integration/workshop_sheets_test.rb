require "test_helper"

# Single-use sheets, the poster admitting once, and only the shop extending a
# client's thirty days (decided on 09/10/2026): a client cannot keep the AI
# running without ever sending a design to a workshop.
class WorkshopSheetsTest < ActionDispatch::IntegrationTest
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
    assert_match "Son affiche n&#39;accueille que", response.body
    assert_not @stranger.reload.attached_to_workshop?

    post join_workshop_path(slug: @lyon.slug)
    assert ClientAffiliation.pending.exists?(client: @stranger, printer: @lyon)
  end

  # --- Numbered single-use sheets -------------------------------------------------

  test "a shop prepares a numbered batch, and numbering carries on across batches" do
    sign_in_as users(:printer)

    post workshop_invites_path, params: { count: 3 }
    post workshop_invites_path, params: { count: 2 }

    assert_equal [ 1, 2, 3, 4, 5 ], @rennes.invites.in_order.pluck(:number)
    assert_equal [ 1, 1, 1, 2, 2 ], @rennes.invites.in_order.pluck(:batch)

    get workshop_invites_path
    assert_select "li", text: /Fiche n° 5/
  end

  test "a batch is capped" do
    sign_in_as users(:printer)

    post workshop_invites_path, params: { count: 10_000 }

    assert_equal WorkshopInvite::BATCH_MAX, @rennes.invites.count
  end

  test "the printed batch carries one page per unspent sheet, each with its own QR code" do
    WorkshopInvite.issue!(@rennes, 2)
    first, second = @rennes.invites.in_order.to_a
    second.revoke!
    sign_in_as users(:printer)

    get print_workshop_invites_path(batch: 1)

    assert_response :success
    assert_select "article.poster", count: 1
    assert_includes response.body, WorkshopQrCode.svg(workshop_sheet_url(code: first.code), size: 200)
  end

  test "a sheet admits a new client at sign-up, once" do
    invite = issue_one(@rennes)

    get workshop_sheet_path(code: invite.code)
    assert_redirected_to workshop_link_path(slug: @rennes.slug)

    post registration_path, params: signup("premiere@example.invalid")
    first = User.find_by!(email_address: "premiere@example.invalid")
    assert_equal @rennes.id, first.active_workshop_id
    assert_equal first.id, invite.reload.used_by_id
    assert ClientAffiliation.accepted.from_sheet.exists?(client: first, printer: @rennes)

    reset!
    get workshop_sheet_path(code: invite.code)
    assert_predicate flash[:alert], :present?, "a spent sheet says so"
    post registration_path, params: signup("seconde@example.invalid")

    second = User.find_by!(email_address: "seconde@example.invalid")
    assert_nil second.active_workshop_id
    assert ClientAffiliation.pending.exists?(client: second, printer: @rennes)
  end

  test "a sheet readmits a former client, which the poster would not" do
    ClientAffiliation.admit!(client: @stranger, printer: @rennes)
    @stranger.update!(workshop_until: 1.minute.ago)
    invite = issue_one(@rennes)
    sign_in_as @stranger

    get workshop_sheet_path(code: invite.code)
    follow_redirect!

    assert_redirected_to new_design_path
    assert @stranger.reload.attached_to_workshop?
    assert_predicate invite.reload, :used?
  end

  test "a withdrawn sheet admits nobody" do
    invite = issue_one(@rennes)
    sign_in_as users(:printer)
    post revoke_workshop_invite_path(invite)
    assert_predicate invite.reload, :revoked?
    sign_out

    get workshop_sheet_path(code: invite.code)
    sign_in_as @stranger
    post join_workshop_path(slug: @rennes.slug)

    assert_nil @stranger.reload.active_workshop_id
  end

  test "a shop cannot withdraw another shop's sheet" do
    invite = issue_one(@lyon)
    sign_in_as users(:printer)

    post revoke_workshop_invite_path(invite)

    assert_response :not_found
    assert_not invite.reload.revoked?
  end

  test "the clients list says which sheet brought each client" do
    invite = issue_one(@rennes)
    ClientAffiliation.admit!(client: @stranger, printer: @rennes, source: :sheet, invite: invite)
    sign_in_as users(:printer)

    get workshop_clients_path

    assert_select "li", text: /Paul Inconnu.*Fiche n° #{invite.number}/m
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

    def issue_one(printer)
      WorkshopInvite.issue!(printer, 1)
      printer.invites.order(:number).last
    end

    def signup(email)
      { user: { email_address: email, password: "motdepasse-test", password_confirmation: "motdepasse-test",
                first_name: "Nouvelle", last_name: "Personne", role: "client", terms: "1" } }
    end
end
