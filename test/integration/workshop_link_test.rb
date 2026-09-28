require "test_helper"

class WorkshopLinkTest < ActionDispatch::IntegrationTest
  test "a printer finds its link, its code and its poster" do
    sign_in_as users(:printer)

    get workshop_link_share_path

    assert_response :success
    assert_select "input[value=?]", workshop_link_url(slug: printers(:rennes).slug)
    assert_select "a[href=?]", workshop_link_poster_path
  end

  test "the qr code comes as an svg and as a png" do
    sign_in_as users(:printer)

    get workshop_link_qr_path(format: :svg)

    assert_response :success
    assert_equal "image/svg+xml", response.media_type
    assert_match(/<svg/, response.body)

    get workshop_link_qr_path(format: :png)

    assert_equal "image/png", response.media_type
    assert_equal "\x89PNG".b, response.body.byteslice(0, 4)
  end

  test "the poster is a page of its own, made to be printed" do
    sign_in_as users(:printer)

    get workshop_link_poster_path

    assert_response :success
    assert_select "svg"
    # The console furniture is not on it.
    assert_select "nav[aria-label]", count: 0
  end

  test "a printer with no listing is sent to make one first" do
    users(:printer_waiting).printer.destroy
    sign_in_as users(:printer_waiting)

    get workshop_link_share_path

    assert_redirected_to edit_workshop_profile_path
  end

  test "only a printer reaches the link screens" do
    [ :client, :designer, :admin ].each do |role|
      sign_in_as users(role)
      get workshop_link_share_path

      assert_response :redirect, "#{role} must not reach it"

      sign_out
    end
  end

  test "a printer never reaches another shop's link" do
    sign_in_as users(:printer_lyon)

    get workshop_link_qr_path(format: :svg)

    assert_response :success
    assert_no_match(/#{printers(:rennes).slug}/, response.headers["Content-Disposition"].to_s)
  end

  # --- Visits ---------------------------------------------------------------

  BROWSER = { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari/605.1.15" }.freeze

  test "a scan of the poster is counted" do
    assert_difference -> { visit_count(:rennes) }, 1 do
      get workshop_link_path(slug: printers(:rennes).slug), headers: BROWSER
    end
  end

  test "a link to a shop nobody can see counts nothing" do
    subscriptions(:rennes).update!(status: "canceled")

    assert_no_difference -> { WorkshopLinkVisit.sum(:count) } do
      get workshop_link_path(slug: printers(:rennes).slug), headers: BROWSER
    end
  end

  test "several people on the same day add up on one row" do
    3.times do
      get workshop_link_path(slug: printers(:rennes).slug), headers: BROWSER
      reset!
    end

    assert_equal 1, WorkshopLinkVisit.where(printer: printers(:rennes)).count
    assert_equal 3, visit_count(:rennes)
  end

  test "a reload or a second scan by the same visitor is not a second visit" do
    3.times { get workshop_link_path(slug: printers(:rennes).slug), headers: BROWSER }

    assert_equal 1, visit_count(:rennes)
  end

  test "the same visitor scanning another shop is a visit for that shop" do
    get workshop_link_path(slug: printers(:rennes).slug), headers: BROWSER
    get workshop_link_path(slug: printers(:lyon).slug), headers: BROWSER

    assert_equal 1, visit_count(:rennes)
    assert_equal 1, visit_count(:lyon)
  end

  test "a link preview, a search engine or a script is not a visitor" do
    [ "WhatsApp/2.23.20 A", "Mozilla/5.0 (compatible; Googlebot/2.1)", "facebookexternalhit/1.1",
      "Slackbot-LinkExpanding 1.0", "curl/8.4.0", "", nil ].each do |agent|
      assert_no_difference -> { visit_count(:rennes) }, "#{agent.inspect} must not count" do
        get workshop_link_path(slug: printers(:rennes).slug), headers: { "User-Agent" => agent }
      end

      reset!
    end
  end

  test "a robot is still sent on its way, and still remembers the shop" do
    get workshop_link_path(slug: printers(:rennes).slug), headers: { "User-Agent" => "curl/8.4.0" }

    assert_redirected_to new_design_path
    assert_equal printers(:rennes).id, session[:printer_id]
  end

  # --- Statistics, which Atelier+ buys --------------------------------------

  test "an Atelier+ shop sees its statistics" do
    sign_in_as users(:printer_lyon)

    get workshop_link_share_path

    assert_response :success
    assert_select "body", text: /#{Regexp.escape(I18n.t('workshop.links.show.statistics'))}/i
  end

  test "a Référencement shop is shown what it would get instead" do
    sign_in_as users(:printer)

    get workshop_link_share_path

    assert_select "body", text: /#{Regexp.escape(I18n.t('workshop.links.show.statistics_locked'))}/i
    assert_select "a[href=?]", workshop_subscription_path
  end

  # Atelier+ that stopped being paid for stops being Atelier+.
  test "statistics go with the subscription, not with the plan alone" do
    subscriptions(:lyon).update!(status: "canceled")
    sign_in_as users(:printer_lyon)

    get workshop_link_share_path

    assert_select "body", text: /#{Regexp.escape(I18n.t('workshop.links.show.statistics_locked'))}/i
  end

  # Lyon's fixtures: "acknowledged" (design fox_dtf, printer lyon — its own
  # funnel) and "found_in_directory" (design fox_screen, printer rennes, but
  # sent to lyon — found some other way).
  test "the requests figure says how many actually confirm the shop's own link" do
    sign_in_as users(:printer_lyon)

    get workshop_link_share_path

    assert_select "body", text: /#{Regexp.escape(I18n.t('workshop.links.show.requests_from_link', count: 1))}/
  end

  test "a shop with only directory-found requests is told none came from its link" do
    print_requests(:acknowledged).destroy
    sign_in_as users(:printer_lyon)

    get workshop_link_share_path

    assert_select "body",
      text: /#{Regexp.escape(I18n.t('workshop.links.show.requests_from_link', count: 0))}/
  end

  test "the breakdown is not shown when there is nothing to break down" do
    print_requests(:acknowledged).destroy
    print_requests(:found_in_directory).destroy
    sign_in_as users(:printer_lyon)

    get workshop_link_share_path

    assert_select "body",
      text: /#{Regexp.escape(I18n.t('workshop.links.show.requests_from_link', count: 0))}/, count: 0
  end

  test "the chart covers thirty days, holes included" do
    WorkshopLinkVisit.create!(printer: printers(:lyon), day: 3.days.ago.to_date, count: 4)

    series = WorkshopLinkVisit.series(printers(:lyon), days: 30)

    assert_equal 30, series.size
    assert_equal 4, series.to_h[3.days.ago.to_date]
    assert_equal 0, series.to_h[1.day.ago.to_date]
  end

  private
    def visit_count(key) = WorkshopLinkVisit.where(printer: printers(key)).sum(:count)
end
