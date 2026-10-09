require "test_helper"

# The help pages (09/10/2026): the clients' questions, the workshop's guide
# and questions, and the sheet a workshop hands to its clients.
class HelpPagesTest < ActionDispatch::IntegrationTest
  test "anyone reads the clients' questions, with today's figures in them" do
    get help_path

    assert_response :success
    assert_select "details summary", minimum: 15
    settings = Rails.application.config.tshirt
    assert_match "#{settings.generation[:quota_per_day]} créations par jour", response.body
    assert_match "#{settings.clients[:attachment_days]} jours à compter de votre arrivée", response.body
    assert_no_match(/%\{/, response.body, "every figure is put in")
  end

  test "the clients' questions are linked from the footer, the shop's page and the sitemap" do
    get workshop_link_path(slug: printers(:rennes).slug)
    assert_select "a[href=?]", help_path, minimum: 2

    get sitemap_path
    assert_includes response.body, help_url
  end

  test "a workshop reads its guide and its questions" do
    sign_in_as users(:printer)

    get workshop_help_path

    assert_response :success
    assert_select "ol li h3", count: 6
    assert_select "details summary", minimum: 10
    assert_match "100 générations par mois", response.body
    assert_select "a[href=?]", workshop_invites_path
    assert_no_match(/%\{/, response.body)
  end

  test "the former single sheet now leads to the numbered sheets" do
    sign_in_as users(:printer)

    get "/atelier/aide/fiche-client"

    assert_redirected_to "/atelier/fiches"
  end

  test "only a workshop reaches its help" do
    [ :client, :designer ].each do |role|
      sign_in_as users(role)
      get workshop_help_path
      assert_response :redirect, "#{role} must not reach it"
      sign_out
    end
  end

  test "a designer reads their guide and questions, with today's figures" do
    sign_in_as users(:designer)

    get designer_help_path

    assert_response :success
    assert_select "ol li h3", count: 6
    assert_select "details summary", minimum: 6
    assert_match "commission de la plateforme (15 %)", response.body
    assert_no_match(/%\{/, response.body)
  end
end
