require "test_helper"

class PasswordsControllerTest < ActionDispatch::IntegrationTest
  test "the reset form is open to a visitor" do
    get new_password_path

    assert_response :success
  end

  test "a known address receives a link" do
    assert_enqueued_emails 1 do
      post passwords_path, params: { email: users(:client).email }
    end

    assert_redirected_to new_session_path
  end

  test "an unknown address gets the same answer, and no email" do
    assert_no_enqueued_emails do
      post passwords_path, params: { email: "inconnue@example.invalid" }
    end

    assert_equal I18n.t("passwords.create.sent"), flash[:notice]
  end

  test "a deleted account receives nothing" do
    assert_no_enqueued_emails do
      post passwords_path, params: { email: users(:deleted_client).email }
    end
  end

  test "a valid token opens the form and resets the password" do
    token = users(:client).password_reset_token

    get edit_password_path(token)
    assert_response :success

    patch password_path(token), params: { password: "un-nouveau-mot-de-passe", password_confirmation: "un-nouveau-mot-de-passe" }

    assert_redirected_to new_session_path
    assert User.authenticate_by(email: users(:client).email, password: "un-nouveau-mot-de-passe")
  end

  test "resetting signs out every other device" do
    user = users(:client)
    user.sessions.create!
    token = user.password_reset_token

    patch password_path(token), params: { password: "un-nouveau-mot-de-passe", password_confirmation: "un-nouveau-mot-de-passe" }

    assert_predicate user.sessions.reload, :empty?
  end

  test "two different passwords change nothing" do
    token = users(:client).password_reset_token

    patch password_path(token), params: { password: "un-nouveau-mot-de-passe", password_confirmation: "pas-le-meme" }

    assert_redirected_to edit_password_path(token)
    assert User.authenticate_by(email: users(:client).email, password: "motdepasse-test")
  end

  test "an invalid token leads back to the request form" do
    get edit_password_path("n-importe-quoi")

    assert_redirected_to new_password_path
    assert_equal I18n.t("passwords.edit.invalid_link"), flash[:alert]
  end
end
