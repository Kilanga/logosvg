require "test_helper"

class DesignerProfilePolicyTest < ActiveSupport::TestCase
  test "an active profile is public" do
    profile = designer_profiles(:ines)

    assert DesignerProfilePolicy.new(nil, profile).show?
    assert DesignerProfilePolicy.new(users(:client), profile).show?
  end

  # Its owner previews it before it goes public; nobody else reads it.
  test "a profile awaiting review is for its owner and the administration" do
    profile = designer_profiles(:nour)

    assert DesignerProfilePolicy.new(profile.user, profile).show?
    assert DesignerProfilePolicy.new(users(:admin), profile).show?
    assert_not DesignerProfilePolicy.new(nil, profile).show?
    assert_not DesignerProfilePolicy.new(users(:client), profile).show?
    assert_not DesignerProfilePolicy.new(users(:designer), profile).show?
  end

  test "only the owner edits" do
    profile = designer_profiles(:ines)

    assert DesignerProfilePolicy.new(profile.user, profile).update?
    assert_not DesignerProfilePolicy.new(users(:designer_away), profile).update?
    assert_not DesignerProfilePolicy.new(users(:admin), profile).update?,
               "an administrator approves, they do not rewrite"
  end

  # Handing identity documents to Stripe is the designer's own act.
  test "onboarding belongs to the designer alone" do
    profile = designer_profiles(:leo)

    assert DesignerProfilePolicy.new(profile.user, profile).onboard?
    assert_not DesignerProfilePolicy.new(users(:admin), profile).onboard?
    assert_not DesignerProfilePolicy.new(users(:designer), profile).onboard?
  end

  test "activating and suspending belong to the administration alone" do
    profile = designer_profiles(:nour)

    assert DesignerProfilePolicy.new(users(:admin), profile).approve?
    assert_not DesignerProfilePolicy.new(profile.user, profile).approve?
    assert_not DesignerProfilePolicy.new(users(:client), profile).approve?
  end

  test "the public scope shows active profiles, to everyone alike" do
    [ nil, users(:client), users(:admin) ].each do |user|
      resolved = DesignerProfilePolicy::Scope.new(user, DesignerProfile).resolve

      assert_includes resolved, designer_profiles(:ines)
      assert_not_includes resolved, designer_profiles(:nour)
      assert_not_includes resolved, designer_profiles(:suspendu)
    end
  end

  test "the administration scope sees everything, and only for an administrator" do
    resolved = DesignerProfilePolicy::AdminScope.new(users(:admin), DesignerProfile).resolve

    assert_includes resolved, designer_profiles(:nour)
    assert_includes resolved, designer_profiles(:suspendu)

    assert_raises Pundit::NotAuthorizedError do
      DesignerProfilePolicy::AdminScope.new(users(:designer), DesignerProfile).resolve
    end
  end
end
