require "test_helper"

# Every form that ends on Stripe's own pages — Checkout, the billing portal,
# Connect onboarding and the Express dashboard — answers with a redirect to
# another domain. Two things stop that redirect without a word on screen:
#
# - Turbo submits forms with fetch, and fetch cannot follow a redirect to a
#   domain that does not open itself to us. Those forms must be submitted the
#   ordinary way: `data-turbo="false"`.
# - `form-action` in the Content Security Policy also governs where a form's
#   redirects may land. Stripe's domains must be listed.
#
# Both failed together on 08/10/2026: Stripe created the session, the shop saw
# nothing happen.
class StripeRedirectionTest < ActionDispatch::IntegrationTest
  STRIPE_FORM_HOSTS = %w[
    https://checkout.stripe.com
    https://billing.stripe.com
    https://connect.stripe.com
  ].freeze

  test "the policy lets a form land on Stripe" do
    get root_path

    form_action = response.headers["Content-Security-Policy"].split(";").map(&:strip)
                          .find { |directive| directive.start_with?("form-action") }

    STRIPE_FORM_HOSTS.each { |host| assert_includes form_action, host }
  end

  test "the shop's billing portal is reached without Turbo" do
    sign_in_as users(:printer)

    get workshop_subscription_path

    assert_select "form[action=?][data-turbo=false]", workshop_subscription_portal_path
  end

  test "the shop's subscribe buttons are submitted without Turbo" do
    subscriptions(:rennes).destroy!
    sign_in_as users(:printer)

    get workshop_subscription_path

    assert_select "form[action=?]", workshop_subscription_path, minimum: 1
    assert_select "form[action=?]:not([data-turbo=false])", workshop_subscription_path, count: 0
  end

  test "a designer's onboarding is reached without Turbo" do
    sign_in_as users(:designer_unpaid)

    get designer_payouts_path

    assert_select "form[action=?][data-turbo=false]", designer_payouts_onboarding_path
  end

  test "a designer's Stripe dashboard is reached without Turbo" do
    sign_in_as users(:designer)

    get designer_payouts_path

    assert_select "form[action=?][data-turbo=false]", designer_payouts_dashboard_path
  end
end
