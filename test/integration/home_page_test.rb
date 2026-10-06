require "test_helper"

class HomePageTest < ActionDispatch::IntegrationTest
  test "a visitor reaches the home page without an account" do
    get root_path

    assert_response :success
    assert_select "h1"
  end

  test "the page is served in French and carries the platform name" do
    get root_path

    assert_select "html[lang=?]", "fr"
    assert_select "title", /#{Regexp.escape(Rails.application.config.tshirt.platform_name)}/
  end

  test "typefaces are self-hosted and no font CDN is contacted" do
    get root_path

    assert_select "link[rel=preload][as=font]", count: 2
    assert_no_match %r{fonts\.googleapis\.com|fonts\.gstatic\.com}, response.body
  end

  test "the content security policy allows only the declared third parties" do
    get root_path
    policy = response.headers["Content-Security-Policy"]

    assert_includes policy, "https://challenges.cloudflare.com"
    assert_includes policy, "https://js.stripe.com"
    assert_includes policy, "https://*.tile.openstreetmap.org"
    assert_includes policy, "object-src 'none'"
    assert_includes policy, "frame-ancestors 'none'"
  end

  # Decided on 06/10/2026, read from config/settings.yml: Atelier+ includes
  # the listing and lifts the monthly generation ceiling, and both start with
  # a free trial. Prices are excluding VAT: the buyers are businesses.
  test "the two plans show their monthly price and the free trial" do
    get root_path

    assert_includes response.body, "29 € HT / mois"
    assert_includes response.body, "59 € HT / mois"
    assert_includes response.body, "100 générations par mois pour vos clients"
    assert_includes response.body, "Générations illimitées pour vos clients"
    assert_includes response.body, I18n.t("public.home.show.plans.includes_listing")
    assert_includes response.body, ERB::Util.html_escape(I18n.t("subscriptions.trial", count: 30))
  end

  test "the subscription terms state the same prices and trial as the home page" do
    get subscription_terms_path

    assert_response :success
    assert_includes response.body, "29 € HT par mois, avec 100 générations"
    assert_includes response.body, "59 € HT par mois, Référencement compris et générations illimitées"
    assert_includes response.body, "La TVA au taux en vigueur"
    assert_includes response.body, "Les 30 premiers jours sont gratuits"
  end

  test "the skip link is the first focusable element" do
    get root_path

    assert_select "a.skip-link[href=?]", "#contenu"
    assert_select "main#contenu"
  end
end
