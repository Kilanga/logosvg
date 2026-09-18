require "test_helper"

class PrinterPolicyTest < ActiveSupport::TestCase
  test "anyone may read a published listing" do
    assert PrinterPolicy.new(nil, printers(:rennes)).show?
    assert PrinterPolicy.new(users(:client), printers(:rennes)).show?
  end

  test "a listing that is not published is for its owner alone" do
    draft = printers(:brouillon)

    assert PrinterPolicy.new(draft.user, draft).show?, "the owner previews their own listing"
    assert_not PrinterPolicy.new(nil, draft).show?
    assert_not PrinterPolicy.new(users(:client), draft).show?
    assert_not PrinterPolicy.new(users(:printer), draft).show?, "another printer is not the owner"
  end

  test "only the owner edits" do
    assert PrinterPolicy.new(users(:printer), printers(:rennes)).update?
    assert_not PrinterPolicy.new(users(:printer_lyon), printers(:rennes)).update?
    assert_not PrinterPolicy.new(users(:admin), printers(:rennes)).update?
  end

  test "a listing is submitted once, from a draft" do
    assert PrinterPolicy.new(users(:printer_draft), printers(:brouillon)).submit?
    assert_not PrinterPolicy.new(users(:printer_waiting), printers(:attente)).submit?
    assert_not PrinterPolicy.new(users(:printer), printers(:rennes)).submit?
  end

  test "publishing belongs to the administration alone" do
    assert PrinterPolicy.new(users(:admin), printers(:attente)).publish?
    assert_not PrinterPolicy.new(users(:printer_waiting), printers(:attente)).publish?
    assert_not PrinterPolicy.new(nil, printers(:attente)).publish?
  end

  test "the directory shows published listings, to everyone alike" do
    [ nil, users(:client), users(:admin) ].each do |user|
      resolved = PrinterPolicy::Scope.new(user, Printer).resolve

      assert_includes resolved, printers(:rennes)
      assert_not_includes resolved, printers(:brouillon)
      assert_not_includes resolved, printers(:attente)
    end
  end

  test "the administration scope sees everything, and only for an administrator" do
    resolved = PrinterPolicy::AdminScope.new(users(:admin), Printer).resolve

    assert_includes resolved, printers(:brouillon)
    assert_includes resolved, printers(:attente)

    assert_raises Pundit::NotAuthorizedError do
      PrinterPolicy::AdminScope.new(users(:printer), Printer).resolve
    end
  end
end
