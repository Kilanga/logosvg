require "test_helper"

# Reported on 14/10/2026: the month's generations were only on the
# subscription page.
class WorkshopDashboardGenerationsTest < ActionDispatch::IntegrationTest
  test "the dashboard shows the month's generations against the plan's allowance" do
    rennes = printers(:rennes)
    rennes.subscription.update_columns(plan: "listing", status: "active")
    quota = PrinterGenerationQuota.for(rennes)
    sign_in_as users(:printer)

    get workshop_dashboard_path

    assert_response :success
    assert_select "#generations_this_month", text: /#{quota.used}\s*\/\s*#{quota.limit}/
  end

  test "a shop without a subscription has no counter to read" do
    sign_in_as users(:printer_draft)

    get workshop_dashboard_path

    assert_select "#generations_this_month", count: 0
  end
end
