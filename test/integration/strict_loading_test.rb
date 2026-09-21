require "test_helper"

# Le développement tourne avec `strict_loading_by_default` (voir
# config/environments/development.rb), la suite de tests non. Un chargement
# paresseux oublié ne se voit donc que dans le navigateur, sur la machine d'un
# humain, et jamais en intégration continue.
#
# C'est ainsi que la lecture de la session a cassé **toutes** les pages
# authentifiées sans qu'aucun des 750 tests ne bronche : `Current.user`
# déréférence la session, et Pundit le lit dès le premier before_action.
#
# Ces cas rejouent chaque écran d'accueil avec le réglage du développement, pour
# que la panne apparaisse ici plutôt que chez l'utilisateur.
class StrictLoadingTest < ActionDispatch::IntegrationTest
  setup do
    @previous = ActiveRecord::Base.strict_loading_by_default
    ActiveRecord::Base.strict_loading_by_default = true
  end

  teardown do
    ActiveRecord::Base.strict_loading_by_default = @previous
    %w[ GENERATOR_URL GENERATOR_API_KEY GENERATOR_USER_KEY ].each { |k| ENV.delete(k) }
  end

  def attach_print_file(design)
    design.print_file.attach(
      io: StringIO.new(<<~SVG), filename: "design.svg", content_type: "image/svg+xml"
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">
          <path d="M0 0h10v10H0z" fill="#1F5F7A"/>
        </svg>
      SVG
    )
  end

  # Posée par test, pas dans le `setup` : l'écran d'état de l'administration
  # interroge le générateur pour de vrai dès que l'adresse existe.
  def generator_configured
    ENV["GENERATOR_URL"] = "http://generator.test"
    ENV["GENERATOR_API_KEY"] = "not-a-key-generator-placeholder"
    ENV["GENERATOR_USER_KEY"] = "not-a-key-hmac-placeholder"
  end

  {
    client: %i[client_dashboard client_designs client_print_requests client_reviews client_account],
    printer: %i[workshop_dashboard workshop_print_requests workshop_link_share
                edit_workshop_profile workshop_subscription],
    designer: %i[designer_dashboard designer_reviews edit_designer_profile designer_payouts],
    admin: %i[admin_dashboard admin_printers admin_designers admin_reviews admin_levels
              admin_blocked_terms admin_status]
  }.each do |role, routes|
    routes.each do |route|
      test "#{route} opens with strict loading on, as development runs it" do
        sign_in_as users(role)

        get public_send("#{route}_path")

        assert_response :success
      end
    end
  end

  test "a public page greets a signed-in visitor without a lazy load" do
    sign_in_as users(:client)

    get root_path

    assert_response :success
  end

  # Le cycle de vie d'un design, écran par écran. Ce parcours passe par des
  # services que les écrans d'accueil ne touchent pas — la fabrique d'enfants,
  # l'aperçu filigrané, la diffusion Turbo — et chacun d'eux a reçu un design
  # tel qu'un `find` le rend, sans association.
  test "a design's page opens with strict loading on" do
    sign_in_as users(:client)

    get design_path(designs(:fox_screen))

    assert_response :success
  end

  test "the watermarked preview is produced with strict loading on" do
    attach_print_file(designs(:fox_screen))
    sign_in_as users(:client)

    get design_image_path(designs(:fox_screen))

    assert_response :success
  end

  test "variants are made with strict loading on" do
    generator_configured
    sign_in_as users(:client)
    designs(:fox_screen).update!(generator_job_id: "job-42")
    stub_request(:post, %r{/jobs/job-42/variants}).to_return(
      body: { job_ids: %w[ v1 v2 ], job_id: "v1", refinements_left: 2 }.to_json
    )

    assert_difference "Design.count", 2 do
      post design_variants_path(designs(:fox_screen))
    end

    assert_response :redirect
  end

  test "a refinement is made with strict loading on" do
    generator_configured
    sign_in_as users(:client)
    designs(:fox_screen).update!(generator_job_id: "job-42")
    stub_request(:post, %r{/jobs/job-42/refine}).to_return(
      body: { job_id: "r1", refinements_left: 1 }.to_json
    )

    post design_refine_path(designs(:fox_screen)), params: { instruction: "un casque rouge" }

    assert_response :redirect
  end

  # Changing a password drops every other session. That sweep used to walk
  # `Current.user.sessions` — an association on a record nobody preloaded, so it
  # raised in development on the one action whose whole point is locking someone
  # out.
  test "changing a password drops the other sessions without a lazy load" do
    user = users(:client)
    elsewhere = user.sessions.create!
    sign_in_as user

    patch client_account_password_path, params: {
      user: { current_password: "motdepasse-test",
              password: "un-nouveau-mot-de-passe",
              password_confirmation: "un-nouveau-mot-de-passe" }
    }

    assert_redirected_to client_account_path
    assert_nil Session.find_by(id: elsewhere.id)
  end
end
