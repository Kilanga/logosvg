require "test_helper"

class PrintRequestPolicyTest < ActiveSupport::TestCase
  # Two sides read it; neither does the other's job.
  test "the client who sent it and the workshop that received it may read it" do
    request = print_requests(:waiting)

    assert PrintRequestPolicy.new(users(:client), request).show?
    assert PrintRequestPolicy.new(users(:printer), request).show?

    assert_not PrintRequestPolicy.new(nil, request).show?
    assert_not PrintRequestPolicy.new(users(:printer_lyon), request).show?
    assert_not PrintRequestPolicy.new(users(:deleted_client), request).show?
    assert_not PrintRequestPolicy.new(users(:admin), request).show?
  end

  test "only a client sends, and only from a design of their own" do
    own = PrintRequest.new(design: designs(:fox_screen), client: users(:client))
    other = PrintRequest.new(design: designs(:other_client_design), client: users(:client))

    assert PrintRequestPolicy.new(users(:client), own).create?
    assert_not PrintRequestPolicy.new(users(:client), other).create?,
               "a client cannot send a design that is not theirs"
    assert_not PrintRequestPolicy.new(users(:printer), own).create?
  end

  # There is nothing to print until the file exists.
  test "a design still generating cannot be sent" do
    pending = PrintRequest.new(design: designs(:pending_design), client: users(:client))

    assert_not PrintRequestPolicy.new(users(:client), pending).create?
  end

  test "the client cancels, the workshop does not" do
    request = print_requests(:waiting)

    assert PrintRequestPolicy.new(users(:client), request).cancel?
    assert_not PrintRequestPolicy.new(users(:printer), request).cancel?
  end

  test "a request already in production is nobody's to cancel" do
    request = print_requests(:waiting)
    request.acknowledge!
    request.quote!
    request.start_production!

    assert_not PrintRequestPolicy.new(users(:client), request).cancel?
  end

  test "the workshop moves an open request along, and the client does not" do
    request = print_requests(:waiting)

    assert PrintRequestPolicy.new(users(:printer), request).update?
    assert_not PrintRequestPolicy.new(users(:client), request).update?
    assert_not PrintRequestPolicy.new(users(:printer_lyon), request).update?
  end

  test "a closed request is no longer moved along" do
    request = print_requests(:waiting).tap(&:cancel!)

    assert_not PrintRequestPolicy.new(users(:printer), request).update?
  end

  test "a client's scope holds to their own requests" do
    resolved = PrintRequestPolicy::Scope.new(users(:client), PrintRequest).resolve

    assert_includes resolved, print_requests(:waiting)
    assert_includes resolved, print_requests(:acknowledged)
  end

  test "a workshop's scope holds to what it received" do
    resolved = PrintRequestPolicy::Scope.new(users(:printer), PrintRequest).resolve

    assert_includes resolved, print_requests(:waiting)
    assert_not_includes resolved, print_requests(:acknowledged),
                        "that one went to Lyon"
    assert_not_includes resolved, print_requests(:forgotten)
  end

  test "a visitor, a designer and an administrator see nothing" do
    [ nil, users(:designer), users(:admin) ].each do |user|
      assert_empty PrintRequestPolicy::Scope.new(user, PrintRequest).resolve
    end
  end
end
