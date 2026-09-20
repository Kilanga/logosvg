require "test_helper"

class SubscriptionsTest < ActionDispatch::IntegrationTest
  # --- What an unpaid listing looks like from outside ----------------------
  #
  # The completion criterion of step 6, asked of every screen that shows a shop
  # rather than only of the scope behind them.

  test "a shop whose subscription lapsed vanishes from the directory" do
    get printers_path

    assert_select "a[href=?]", printer_path(printers(:rennes))

    subscriptions(:rennes).update!(status: "canceled")
    get printers_path

    assert_select "a[href=?]", printer_path(printers(:rennes)), count: 0
  end

  # Refused the same way a draft listing is: Pundit turns it away rather than
  # letting anyone holding the link keep reading it.
  test "and from its own public page" do
    get printer_path(printers(:rennes))

    assert_response :success

    subscriptions(:rennes).update!(status: "canceled")
    get printer_path(printers(:rennes))

    assert_response :redirect
  end

  # Its owner still previews it — that is what "aperçu public" means on the
  # edit screen, and it is how they check the listing before paying again.
  test "but its owner still reaches it" do
    subscriptions(:rennes).update!(status: "canceled")
    sign_in_as users(:printer)

    get printer_path(printers(:rennes))

    assert_response :success
  end

  test "and from the shop's sharing link" do
    subscriptions(:rennes).update!(status: "canceled")
    sign_in_as users(:client)

    get workshop_link_path(slug: printers(:rennes).slug)

    assert_redirected_to printers_path
  end

  test "and from the workshops a design could be sent to" do
    designs(:fox_screen).print_file.attach(
      io: StringIO.new(svg), filename: "design.svg", content_type: "image/svg+xml"
    )
    subscriptions(:rennes).update!(status: "canceled")
    sign_in_as users(:client)

    get design_path(designs(:fox_screen))

    assert_select "a[href=?]", printer_path(printers(:rennes)), count: 0
  end

  # The owner keeps their own view of it: paying is how you come back.
  test "the shop still reaches its own space when the subscription lapses" do
    subscriptions(:rennes).update!(status: "canceled")
    sign_in_as users(:printer)

    get workshop_dashboard_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(I18n.t('workshop.dashboards.show.not_visible'))}/i
  end

  # --- The subscription screen ---------------------------------------------

  test "a printer sees their plan and a way into the portal" do
    sign_in_as users(:printer)

    get workshop_subscription_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(I18n.t('enums.subscription.plan.listing'))}/i
    assert_select "form[action=?]", workshop_subscription_portal_path
  end

  test "a printer with no subscription is shown the plans" do
    subscriptions(:rennes).destroy
    sign_in_as users(:printer)

    get workshop_subscription_path

    assert_response :success
    assert_select "form[action=?]", workshop_subscription_path
  end

  # Without keys there is nothing to redirect to, and saying so beats a 500.
  test "subscribing without Stripe configured says so rather than failing" do
    subscriptions(:rennes).destroy
    sign_in_as users(:printer)

    post workshop_subscription_path, params: { plan: "listing" }

    assert_redirected_to workshop_subscription_path
    assert_equal I18n.t("subscriptions.errors.not_configured"), flash[:alert]
  end

  test "a plan nobody sells is refused" do
    sign_in_as users(:printer)

    post workshop_subscription_path, params: { plan: "gratuit" }

    assert_redirected_to workshop_subscription_path
  end

  test "only a printer reaches the subscription screen" do
    [ :client, :designer, :admin ].each do |role|
      sign_in_as users(role)
      get workshop_subscription_path

      assert_response :redirect, "#{role} must not reach it"

      sign_out
    end
  end

  # --- The webhook endpoint -------------------------------------------------

  test "an unsigned webhook is refused" do
    ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test_placeholder_not_real"

    post stripe_webhook_path, params: { id: "evt_x", type: "invoice.paid" }.to_json,
         headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :bad_request
  ensure
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end

  test "a webhook with a bad signature is refused" do
    ENV["STRIPE_WEBHOOK_SECRET"] = "whsec_test_placeholder_not_real"

    post stripe_webhook_path, params: "{}",
         headers: { "CONTENT_TYPE" => "application/json", "Stripe-Signature" => "t=1,v1=nope" }

    assert_response :bad_request
  ensure
    ENV.delete("STRIPE_WEBHOOK_SECRET")
  end

  test "a webhook arriving with no signing secret configured is not acted on" do
    post stripe_webhook_path, params: "{}", headers: { "CONTENT_TYPE" => "application/json" }

    assert_response :service_unavailable
  end

  # Stripe is not a visitor: no session, no CSRF token, no redirect to sign in.
  test "the webhook endpoint never asks Stripe to sign in" do
    post stripe_webhook_path, params: "{}", headers: { "CONTENT_TYPE" => "application/json" }

    assert_not_equal 302, response.status
  end

  private
    def svg
      %(<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 10 10">) +
        %(<path d="M0 0h10v10H0z" fill="#1F5F7A"/></svg>)
    end
end
