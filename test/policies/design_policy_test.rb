require "test_helper"

class DesignPolicyTest < ActiveSupport::TestCase
  test "a design is readable by the client who made it, and by nobody else" do
    design = designs(:fox_screen)

    assert DesignPolicy.new(users(:client), design).show?
    assert_not DesignPolicy.new(nil, design).show?
    assert_not DesignPolicy.new(users(:deleted_client), design).show?
    assert_not DesignPolicy.new(users(:printer), design).show?
    assert_not DesignPolicy.new(users(:admin), design).show?,
               "an administrator has no business reading a client's design"
  end

  test "only a client generates" do
    assert DesignPolicy.new(users(:client), Design.new).create?
    assert_not DesignPolicy.new(users(:printer), Design.new).create?
    assert_not DesignPolicy.new(users(:designer), Design.new).create?
    assert_not DesignPolicy.new(nil, Design.new).create?
  end

  # The preview is the one file a client may download; the print file is not.
  test "the preview follows ownership, not the state of the design" do
    assert DesignPolicy.new(users(:client), designs(:fox_screen)).image?
    assert DesignPolicy.new(users(:client), designs(:pending_design)).image?
    assert_not DesignPolicy.new(users(:printer), designs(:fox_screen)).image?
  end

  # A ready design never changes: only a ready one can father children.
  test "a design is taken further only once it is ready, and only by its owner" do
    ready = designs(:fox_screen)
    pending = designs(:pending_design)

    assert DesignPolicy.new(users(:client), ready).variants?
    assert DesignPolicy.new(users(:client), ready).refine?

    assert_not DesignPolicy.new(users(:client), pending).variants?,
               "nothing to build on while the generation is still running"
    assert_not DesignPolicy.new(users(:client), pending).refine?
    assert_not DesignPolicy.new(users(:printer), ready).variants?
  end

  test "the scope holds a client to their own designs" do
    resolved = DesignPolicy::Scope.new(users(:client), Design).resolve

    assert_includes resolved, designs(:fox_screen)
    assert_includes resolved, designs(:fox_dtf)
    assert_not_includes resolved, designs(:other_client_design)
  end

  test "a soft-deleted design leaves the scope" do
    designs(:fox_screen).soft_delete!

    assert_not_includes DesignPolicy::Scope.new(users(:client), Design).resolve, designs(:fox_screen)
  end

  test "a visitor's scope is empty, not everyone's designs" do
    assert_empty DesignPolicy::Scope.new(nil, Design).resolve
  end
end
