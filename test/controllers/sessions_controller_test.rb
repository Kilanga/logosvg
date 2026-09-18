require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  test "the sign-in form is open to a visitor" do
    get new_session_path

    assert_response :success
  end

  test "the right credentials open a session" do
    post session_path, params: { email: users(:client).email, password: "motdepasse-test" }

    assert_redirected_to "/mon-espace"
  end

  test "the address is matched whatever the case" do
    post session_path, params: { email: users(:client).email.upcase, password: "motdepasse-test" }

    assert_redirected_to "/mon-espace"
  end

  test "a wrong password says the same thing as an unknown address" do
    post session_path, params: { email: users(:client).email, password: "pas-le-bon" }
    wrong_password = flash[:alert]

    post session_path, params: { email: "inconnue@example.invalid", password: "motdepasse-test" }

    assert_equal wrong_password, flash[:alert], "the form must not reveal which accounts exist"
    assert_redirected_to new_session_path
  end

  test "a deleted account cannot sign back in" do
    post session_path, params: { email: users(:deleted_client).email, password: "motdepasse-test" }

    assert_redirected_to new_session_path
    assert_equal I18n.t("sessions.create.failed"), flash[:alert]
  end

  test "signing in returns to the page that required it" do
    get "/mon-espace"
    assert_redirected_to new_session_path

    post session_path, params: { email: users(:client).email, password: "motdepasse-test" }

    assert_redirected_to "http://www.example.com/mon-espace"
  end

  test "signing out ends the session and returns home" do
    sign_in_as users(:client)

    delete session_path

    assert_redirected_to root_path
    get "/mon-espace"
    assert_redirected_to new_session_path
  end
end
