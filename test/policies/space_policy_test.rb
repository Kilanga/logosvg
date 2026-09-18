require "test_helper"

# Each space admits exactly one role. Tested in both directions: the role that
# belongs there gets in, and every other role — administrators included — does
# not.
class SpacePolicyTest < ActiveSupport::TestCase
  SPACES = {
    ClientSpacePolicy => :client,
    PrinterSpacePolicy => :printer,
    DesignerSpacePolicy => :designer,
    AdminSpacePolicy => :admin
  }.freeze

  test "each space lets its own role in" do
    SPACES.each do |policy, fixture|
      assert policy.new(users(fixture), :space).show?,
             "#{policy} should admit #{fixture}"
    end
  end

  test "each space turns every other role away" do
    SPACES.each do |policy, allowed|
      (SPACES.values - [ allowed ]).each do |other|
        assert_not policy.new(users(other), :space).show?,
                   "#{policy} must not admit #{other}"
      end
    end
  end

  test "an administrator does not roam the other spaces" do
    assert_not ClientSpacePolicy.new(users(:admin), :space).show?
    assert_not PrinterSpacePolicy.new(users(:admin), :space).show?
    assert_not DesignerSpacePolicy.new(users(:admin), :space).show?
  end

  test "a visitor with no account enters nothing" do
    SPACES.each_key do |policy|
      assert_not policy.new(nil, :space).show?, "#{policy} must not admit a visitor"
    end
  end

  test "a deleted account enters nothing, even with the right role" do
    assert_not ClientSpacePolicy.new(users(:deleted_client), :space).show?
  end

  test "the base policy refuses to answer without a role" do
    assert_raises NoMethodError do
      SpacePolicy.new(users(:client), :space).show?
    end
  end
end
