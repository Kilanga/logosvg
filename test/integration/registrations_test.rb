require "test_helper"

class RegistrationsTest < ActionDispatch::IntegrationTest
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
    post registration_path, params: valid_params

    follow_redirect!

    assert_response :success
  end

  test "an unknown role falls back to client rather than raising" do
    post registration_path, params: valid_params(role: "sorcier")

    assert_predicate User.order(:created_at).last, :client?
  end

  test "nobody signs up as an administrator" do
    assert_difference "User.count", 1 do
      post registration_path, params: valid_params(role: "admin")
    end

    assert_predicate User.order(:created_at).last, :client?
    assert_empty User.admin.where.not(id: users(:admin).id)
  end

  test "terms left unchecked stop the account being created" do
    assert_no_difference "User.count" do
      post registration_path, params: valid_params.tap { |p| p[:user].delete(:terms) }
    end

    assert_response :unprocessable_entity
  end

  test "an address already registered stops the account being created" do
    assert_no_difference "User.count" do
      post registration_path, params: valid_params(email_address: users(:client).email_address)
    end

    assert_response :unprocessable_entity
  end

  test "someone already signed in is refused the form" do
    sign_in_as users(:client)

    get new_registration_path

    assert_redirected_to "/mon-espace"
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
