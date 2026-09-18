require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "an account needs a name, an email and accepted terms" do
    user = User.new

    assert_not user.valid?
    assert user.errors.include?(:email)
    assert user.errors.include?(:first_name)
    assert user.errors.include?(:last_name)
    assert user.errors.include?(:terms_accepted_at)
  end

  test "email is stored trimmed and lowercased" do
    user = build_user(email: "  Claire.Martin@Example.INVALID  ")

    assert user.save
    assert_equal "claire.martin@example.invalid", user.email
  end

  test "email must be unique whatever the case" do
    user = build_user(email: users(:client).email.upcase)

    assert_not user.valid?
    assert user.errors.include?(:email)
  end

  test "an address that is not an address is refused" do
    assert_not build_user(email: "claire[at]example").valid?
  end

  test "phone keeps only digits and a leading plus" do
    user = build_user(phone: "+33 6 12 34 56 78")

    assert user.save
    assert_equal "+33612345678", user.phone
  end

  test "each role is a distinct account type" do
    assert users(:client).client?
    assert users(:printer).printer?
    assert users(:designer).designer?
    assert users(:admin).admin?
  end

  test "a role outside the four is refused" do
    # `validate: true` on the enum turns an unknown value into a validation
    # error rather than an exception, so a bad form value cannot 500 the page.
    user = build_user(role: "superadmin")

    assert_not user.valid?
    assert user.errors.include?(:role)
  end

  test "a new account is a client unless told otherwise" do
    assert_predicate User.new, :client?
  end

  test "only client, printer and designer can be chosen at sign-up" do
    assert_equal %w[ client printer designer ], User::SELF_ASSIGNABLE_ROLES
    assert_not_includes User::SELF_ASSIGNABLE_ROLES, "admin"
  end

  test "full name joins the parts that are there" do
    assert_equal "Claire Martin", users(:client).full_name
    assert_equal "Claire", build_user(first_name: "Claire", last_name: nil).full_name
  end

  test "soft delete keeps the record but ends every session" do
    user = users(:client)
    user.sessions.create!

    user.soft_delete!

    assert_not_predicate user, :active?
    assert_predicate user.sessions.reload, :empty?
    assert User.exists?(user.id), "the record is kept until the purge task runs"
  end

  test "active and deleted scopes split the accounts" do
    assert_includes User.active, users(:client)
    assert_not_includes User.active, users(:deleted_client)
    assert_includes User.deleted, users(:deleted_client)
  end

  test "a deleted account cannot authenticate even with the right password" do
    assert_nil User.authenticate_by(email: users(:deleted_client).email, password: "motdepasse-test")
  end

  test "an active account authenticates with the right password" do
    assert_equal users(:client), User.authenticate_by(email: users(:client).email, password: "motdepasse-test")
  end

  test "a wrong password never authenticates" do
    assert_nil User.authenticate_by(email: users(:client).email, password: "pas-le-bon")
  end

  private
    def build_user(**attributes)
      User.new({
        email: "nouvelle@example.invalid",
        password: "motdepasse-test",
        first_name: "Nouvelle",
        last_name: "Personne",
        terms_accepted_at: Time.current
      }.merge(attributes))
    end
end
