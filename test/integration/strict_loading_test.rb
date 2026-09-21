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

  teardown { ActiveRecord::Base.strict_loading_by_default = @previous }

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
