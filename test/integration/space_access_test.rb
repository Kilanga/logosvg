require "test_helper"

# The completion criterion for step 1: each role reaches its own space and no
# other. Tested for every pair, not just the obvious ones.
class SpaceAccessTest < ActionDispatch::IntegrationTest
  SPACES = {
    client: "/mon-espace",
    printer: "/atelier",
    designer: "/studio",
    admin: "/admin"
  }.freeze

  test "a visitor without an account is sent to sign in, never into a space" do
    SPACES.each_value do |path|
      get path

      assert_redirected_to new_session_path
    end
  end

  test "each role reaches its own space" do
    SPACES.each do |role, path|
      sign_in_as users(role)
      get path

      assert_response :success, "#{role} should reach #{path}"

      sign_out
    end
  end

  test "each role is turned away from every other space" do
    SPACES.each_key do |role|
      sign_in_as users(role)

      (SPACES.keys - [ role ]).each do |other|
        get SPACES[other]

        assert_redirected_to SPACES[role], "#{role} must not open #{SPACES[other]}"
        assert_equal I18n.t("flash.unauthorized"), flash[:alert]
      end

      sign_out
    end
  end

  test "an administrator does not roam the other spaces" do
    sign_in_as users(:admin)

    get "/mon-espace"
    assert_redirected_to "/admin"

    get "/atelier"
    assert_redirected_to "/admin"

    get "/studio"
    assert_redirected_to "/admin"
  end

  test "signing in lands on the space of the role" do
    SPACES.each do |role, path|
      post session_path, params: { email_address: users(role).email_address, password: "motdepasse-test" }

      assert_redirected_to path

      delete session_path
    end
  end

  test "the home page stays open to everyone" do
    get root_path
    assert_response :success

    sign_in_as users(:client)
    get root_path
    assert_response :success
  end
end
