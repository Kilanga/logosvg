require "test_helper"

class AdminPrintersTest < ActionDispatch::IntegrationTest
  test "the administration sees every listing, whatever its status" do
    sign_in_as users(:admin)

    get admin_printers_path

    assert_response :success
    assert_includes response.body, printers(:attente).name
    assert_includes response.body, printers(:brouillon).name
    assert_includes response.body, printers(:rennes).name
  end

  test "nobody else reaches the queue" do
    [ :client, :printer, :designer ].each do |role|
      sign_in_as users(role)
      get admin_printers_path

      assert_response :redirect, "#{role} must not open the review queue"

      sign_out
    end
  end

  test "an administrator publishes a listing awaiting review" do
    sign_in_as users(:admin)

    patch admin_printer_path(printers(:attente)), params: { status: "published" }

    assert_redirected_to admin_printers_path
    assert_predicate printers(:attente).reload, :published?
  end

  # Asserted on the link rather than on the page body: the confirmation flash
  # names the shop too, and would make either direction pass for the wrong
  # reason.
  test "a published listing appears in the directory straight away" do
    sign_in_as users(:admin)
    patch admin_printer_path(printers(:attente)), params: { status: "published" }
    sign_out

    get printers_path

    assert_select "a[href=?]", printer_path(printers(:attente))
  end

  test "an administrator suspends a listing, which leaves the directory" do
    sign_in_as users(:admin)

    patch admin_printer_path(printers(:rennes)), params: { status: "suspended" }
    assert_predicate printers(:rennes).reload, :suspended?

    sign_out
    get printers_path

    assert_select "a[href=?]", printer_path(printers(:rennes)), count: 0
  end

  test "a printer cannot publish their own listing through the admin route" do
    sign_in_as users(:printer_waiting)

    patch admin_printer_path(printers(:attente)), params: { status: "published" }

    assert_predicate printers(:attente).reload, :pending_review?
  end

  test "any status other than the two decisions is refused" do
    sign_in_as users(:admin)

    patch admin_printer_path(printers(:attente)), params: { status: "draft" }

    assert_response :bad_request
    assert_predicate printers(:attente).reload, :pending_review?
  end

  # The "waiting" half of the screen already draws its empty state; the
  # "decided" half did not, and rendered nothing at all below its own heading.
  test "no decided listing yet is said, not left blank" do
    Printer.where.not(id: printers(:attente).id).update_all(status: "pending_review")
    sign_in_as users(:admin)

    get admin_printers_path

    assert_select "body", text: /#{Regexp.escape(I18n.t('admin.printers.index.all', count: 0))}/
  end
end
