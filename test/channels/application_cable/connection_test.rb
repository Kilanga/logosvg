require "test_helper"

# Le socket a sa propre lecture de session, indépendante de celle des
# contrôleurs. Elle a donc pu garder le chargement paresseux que le reste de
# l'application avait perdu — et les 750 tests n'en savaient rien, parce que la
# suite ne tourne pas avec `strict_loading_by_default`.
#
# Ce cas rejoue l'ouverture du socket avec le réglage du développement. Une
# panne ici ne se voit pas à l'écran : Turbo retente en silence, et l'écran
# reste figé sur « génération en cours » pendant que le travail, lui, avance.
class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  tests ApplicationCable::Connection

  setup do
    @previous = ActiveRecord::Base.strict_loading_by_default
    ActiveRecord::Base.strict_loading_by_default = true
  end

  teardown { ActiveRecord::Base.strict_loading_by_default = @previous }

  test "opens with strict loading on, as development runs it" do
    user = users(:client)
    session = user.sessions.create!

    cookies.signed[:session_id] = session.id
    connect

    assert_equal user, connection.current_user
  end

  test "refuses a visitor without a session" do
    assert_reject_connection { connect }
  end

  test "refuses a cookie pointing at a session that no longer exists" do
    user = users(:client)
    session = user.sessions.create!
    cookies.signed[:session_id] = session.id
    session.destroy!

    assert_reject_connection { connect }
  end
end
