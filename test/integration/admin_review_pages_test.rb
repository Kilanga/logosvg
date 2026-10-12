require "test_helper"

# Reported on 12/10/2026: an administrator could not open a printer's listing
# before deciding on it, nor one already in the "other listings" list. Every
# page the admin queues link to must open for an administrator, whatever the
# state of what it shows.
class AdminReviewPagesTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "every listing linked from the admin queue opens, whatever its state" do
    get admin_printers_path
    links = css_select("a[href^='/imprimeurs/']").map { |a| a["href"] }.uniq
    assert_not_empty links

    links.each do |href|
      get href
      assert_response :success, "#{href} should open for an administrator"
    end
  end

  test "a listing waiting for review opens for an administrator, marked as not public" do
    get printer_path(printers(:attente))

    assert_response :success
    assert_select "p", text: /#{Regexp.escape(I18n.t("public.printers.show.admin_preview",
                                                       status: I18n.t("enums.printer.status.pending_review").downcase))}/
  end

  test "a draft and a suspended listing open for an administrator too" do
    get printer_path(printers(:brouillon))
    assert_response :success

    printers(:nantes).update_columns(status: Printer.statuses[:suspended])
    get printer_path(printers(:nantes))
    assert_response :success
  end

  test "every designer profile linked from the admin queue opens, whatever its state" do
    get admin_designers_path
    links = css_select("a[href^='/graphistes/']").map { |a| a["href"] }.uniq
    assert_not_empty links

    links.each do |href|
      get href
      assert_response :success, "#{href} should open for an administrator"
    end
  end

  test "a designer profile waiting for review says it is an administrator's reading" do
    get designer_path(designer_profiles(:nour))

    assert_response :success
    assert_select "p", text: I18n.t("public.designers.show.admin_preview_body")
  end

  test "every review linked from the admin list opens, in every filter" do
    get admin_reviews_path
    filters = css_select("a[href^='/admin/verifications?']").map { |a| a["href"] }.uniq
    reviews = []
    ([ admin_reviews_path ] + filters).each do |href|
      get href
      assert_response :success, "#{href} should open for an administrator"
      reviews |= css_select("a[href^='/admin/verifications/']").map { |a| a["href"] }
    end
    assert_not_empty reviews

    reviews.each do |href|
      get href
      assert_response :success, "#{href} should open for an administrator"
    end
  end

  test "a visitor still cannot open a listing that is not public" do
    sign_out
    get printer_path(printers(:attente))

    assert_response :redirect
  end
end
