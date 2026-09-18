require "test_helper"

class UserPolicyTest < ActiveSupport::TestCase
  test "a visitor may sign up" do
    assert UserPolicy.new(nil, User.new).create?
    assert UserPolicy.new(nil, User.new).new?
  end

  test "someone already signed in may not create another account from the form" do
    assert_not UserPolicy.new(users(:client), User.new).create?
    assert_not UserPolicy.new(users(:admin), User.new).create?
  end

  test "everything is forbidden until a policy allows it" do
    policy = ApplicationPolicy.new(users(:admin), Object.new)

    assert_not policy.index?
    assert_not policy.show?
    assert_not policy.create?
    assert_not policy.update?
    assert_not policy.destroy?
  end
end
