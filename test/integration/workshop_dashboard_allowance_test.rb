require "test_helper"

# Reported on 14/10/2026: the month's allowance was only on the subscription
# page. Counted in print requests since 20/10/2026.
class WorkshopDashboardAllowanceTest < ActionDispatch::IntegrationTest
  test "the dashboard shows the month's requests against the plan's allowance" do
    rennes = printers(:rennes)
    rennes.subscription.update_columns(plan: "listing", status: "active")
    quota = PrinterRequestQuota.for(rennes)
    sign_in_as users(:printer)

    get workshop_dashboard_path

    assert_response :success
    assert_select "#allowance_this_month", text: /#{quota.used}\s*\/\s*#{quota.limit}/
  end

  test "a shop without a subscription has no counter to read" do
    sign_in_as users(:printer_draft)

    get workshop_dashboard_path

    assert_select "#allowance_this_month", count: 0
  end

  test "the subscription page says how many requests the month has counted" do
    sign_in_as users(:printer)

    get workshop_subscription_path

    assert_response :success
    assert_select "#allowance_this_month", text: /#{I18n.t("workshop.subscriptions.show.requests_this_month")}/
  end
end
