require "test_helper"

# A client belongs to one workshop, and only with that workshop's agreement
# (09/10/2026). See docs/SPEC.md, "Rattachement d'un client à un atelier".
class WorkshopClientsTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @rennes = printers(:rennes)
    @lyon = printers(:lyon)
    @stranger = User.create!(email_address: "inconnu@example.invalid", password: "motdepasse-test",
                             first_name: "Paul", last_name: "Inconnu", role: "client",
                             terms_accepted_at: Time.current)
  end

  # --- The shop's page --------------------------------------------------------

  test "the shop's page presents the shop and offers an account" do
    get workshop_link_path(slug: @rennes.slug)

    assert_response :success
    assert_select "h1", text: /Sérigraphie du Thabor/i
    assert_select "a[href=?]", new_registration_path
    assert_select "a[href=?]", new_session_path
    assert_match "valide chacun de ses nouveaux clients", response.body
  end

  test "the code is taken, then dropped from the address" do
    get workshop_invite_path(slug: @rennes.slug, code: @rennes.invite_code)

    assert_redirected_to workshop_link_path(slug: @rennes.slug)
    follow_redirect!
    assert_match "votre compte lui sera rattaché", response.body
  end

  test "the code compares without regard to case" do
    get workshop_invite_path(slug: @rennes.slug, code: @rennes.invite_code.upcase)
    follow_redirect!

    assert_match "votre compte lui sera rattaché", response.body
  end

  test "signing in from the shop's page comes back to it" do
    get workshop_link_path(slug: @lyon.slug)
    post session_path, params: { email_address: @stranger.email_address, password: "motdepasse-test" }

    assert_redirected_to workshop_link_url(slug: @lyon.slug)
  end

  # --- Asking, from the directory -----------------------------------------------

  test "a client without a shop asks, and the shop is told by email" do
    sign_in_as @stranger

    assert_enqueued_email_with AffiliationMailer, :requested, args: ->(args) { args.first.printer_id == @lyon.id } do
      post join_workshop_path(slug: @lyon.slug)
    end

    assert_redirected_to client_dashboard_path
    assert ClientAffiliation.pending.exists?(client: @stranger, printer: @lyon)
    assert_nil @stranger.reload.workshop_id
  end

  test "asking twice is one request" do
    sign_in_as @stranger

    2.times { post join_workshop_path(slug: @lyon.slug) }

    assert_equal 1, ClientAffiliation.where(client: @stranger).count
  end

  test "asking another shop replaces the request still open" do
    sign_in_as @stranger
    post join_workshop_path(slug: @lyon.slug)
    post join_workshop_path(slug: @rennes.slug)

    assert ClientAffiliation.cancelled.exists?(client: @stranger, printer: @lyon)
    assert ClientAffiliation.pending.exists?(client: @stranger, printer: @rennes)
  end

  test "with the code in the visit, joining needs no answer" do
    get workshop_invite_path(slug: @lyon.slug, code: @lyon.invite_code)
    sign_in_as @stranger

    assert_no_enqueued_emails do
      post join_workshop_path(slug: @lyon.slug)
    end

    assert_equal @lyon.id, @stranger.reload.workshop_id
  end

  test "a client waiting on a shop cannot create, and is told why" do
    sign_in_as @stranger
    post join_workshop_path(slug: @lyon.slug)

    get new_design_path
    assert_redirected_to client_dashboard_path

    get new_design_upload_path
    assert_redirected_to client_dashboard_path

    assert_no_difference "Design.count" do
      post designs_path, params: { design: { prompt: "un renard", technique: "screen_printing", style: "illustration" } }
    end

    get client_dashboard_path
    assert_match "en attente de sa réponse", response.body
  end

  test "a shop no longer listed lets nobody in, even with its code" do
    get workshop_invite_path(slug: printers(:brouillon).slug, code: printers(:brouillon).invite_code)

    assert_redirected_to printers_path
  end

  test "a professional account cannot join a shop" do
    sign_in_as users(:designer)

    post join_workshop_path(slug: @lyon.slug)

    assert_redirected_to "/studio"
    assert_not ClientAffiliation.exists?(client: users(:designer))
  end

  # --- Answering, in the workshop's space -----------------------------------------

  test "the shop sees the request and accepts it; the client is told and can create" do
    affiliation = ClientAffiliation.request!(client: @stranger, printer: @rennes)
    sign_in_as users(:printer)

    get workshop_clients_path
    assert_select "li", text: /Paul Inconnu/

    assert_enqueued_email_with AffiliationMailer, :accepted, args: [ affiliation ] do
      post accept_workshop_client_request_path(affiliation)
    end

    assert_redirected_to workshop_clients_path
    assert_equal @rennes.id, @stranger.reload.workshop_id
    assert_predicate affiliation.reload, :accepted?
  end

  test "the shop refuses; the client is told and still cannot create" do
    affiliation = ClientAffiliation.request!(client: @stranger, printer: @rennes)
    sign_in_as users(:printer)

    assert_enqueued_email_with AffiliationMailer, :declined, args: [ affiliation ] do
      post decline_workshop_client_request_path(affiliation)
    end

    assert_nil @stranger.reload.workshop_id
    assert_predicate affiliation.reload, :declined?
  end

  test "a shop cannot answer another shop's request" do
    affiliation = ClientAffiliation.request!(client: @stranger, printer: @lyon)
    sign_in_as users(:printer)

    post accept_workshop_client_request_path(affiliation)

    assert_response :not_found
    assert_nil @stranger.reload.workshop_id
  end

  test "the dashboard says when a request is waiting" do
    ClientAffiliation.request!(client: @stranger, printer: @rennes)
    sign_in_as users(:printer)

    get workshop_dashboard_path

    assert_select "a[href=?]", workshop_clients_path, text: /1 demande attend votre réponse/
  end

  test "a shop takes a client off its list; the client is told and stops creating on its plan" do
    client = users(:client)
    sign_in_as users(:printer)

    assert_enqueued_emails 1 do
      delete workshop_client_path(client)
    end

    assert_nil client.reload.workshop_id
  end

  test "a shop cannot take off another shop's client" do
    client = users(:client)
    sign_in_as users(:printer_lyon)

    delete workshop_client_path(client)

    assert_response :not_found
    assert_equal @rennes.id, client.reload.workshop_id
  end

  # --- The code ------------------------------------------------------------------

  test "a new code stops the old one admitting anyone" do
    old_code = @rennes.invite_code
    sign_in_as users(:printer)

    post workshop_link_code_path

    assert_not_equal old_code, @rennes.reload.invite_code
    sign_out

    get workshop_invite_path(slug: @rennes.slug, code: old_code)
    sign_in_as @stranger
    post join_workshop_path(slug: @rennes.slug)

    assert_nil @stranger.reload.workshop_id
    assert ClientAffiliation.pending.exists?(client: @stranger, printer: @rennes)
  end

  # --- Reprises follow the shop ----------------------------------------------------

  test "a client who moved shops cannot spend the old shop's generations on reprises" do
    client = users(:client)
    design = Design.create!(user: client, printer: @rennes, prompt: "un renard", technique: "screen_printing",
                            style: "illustration", print_width_cm: 25, status: "ready",
                            generator_job_id: "job-#{SecureRandom.hex(4)}", chosen_at: Time.current)
    client.update!(workshop_id: @lyon.id)
    sign_in_as client

    post design_variants_path(design)

    assert_redirected_to design_path(design)
    assert_equal I18n.t("client.designs.take_it_further.other_workshop").squish, flash[:alert].squish
    assert_equal 0, GenerationQuota.for(client).used
  end
end
