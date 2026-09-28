require "test_helper"

class WorkshopLinkChannelsTest < ActionDispatch::IntegrationTest
  BROWSER = { "User-Agent" => "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) Safari/605.1.15" }.freeze

  setup do
    @lyon = printers(:lyon)       # Atelier+
    @rennes = printers(:rennes)   # Référencement
  end

  # --- Where a visit is counted ----------------------------------------------------

  test "a scan of the poster is counted as a qr visit" do
    get workshop_link_path(slug: @lyon.slug, s: "qr"), headers: BROWSER

    assert_equal({ "qr" => 1 }, sources(@lyon))
  end

  test "a click on the plain link is counted as a link visit" do
    get workshop_link_path(slug: @lyon.slug), headers: BROWSER

    assert_equal({ "link" => 1 }, sources(@lyon))
  end

  test "a named link is counted under its own key" do
    @lyon.link_channels.create!(label: "Salon de Rennes")

    get workshop_link_path(slug: @lyon.slug, s: "salon-de-rennes"), headers: BROWSER

    assert_equal({ "salon-de-rennes" => 1 }, sources(@lyon))
  end

  test "a source nobody made is the plain link, and cannot fill the table" do
    get workshop_link_path(slug: @lyon.slug, s: "n-importe-quoi"), headers: BROWSER

    assert_equal({ "link" => 1 }, sources(@lyon))
  end

  test "another shop's channel counts nothing here" do
    @rennes.link_channels.create!(label: "Flyer")

    get workshop_link_path(slug: @lyon.slug, s: "flyer"), headers: BROWSER

    assert_equal({ "link" => 1 }, sources(@lyon))
  end

  test "the visitor is sent to the creation screen whatever the source" do
    get workshop_link_path(slug: @lyon.slug, s: "qr"), headers: BROWSER

    assert_redirected_to new_design_path
    assert_equal @lyon.id, session[:printer_id]
  end

  # --- What the QR codes encode -----------------------------------------------------

  # The drawing is deterministic, so what a page carries can be compared with
  # what the same URL draws: a code for the wrong URL would be a different SVG.
  test "the poster's qr code carries the qr source" do
    sign_in_as users(:printer_lyon)

    get workshop_link_poster_path

    assert_includes response.body, WorkshopQrCode.svg(workshop_link_url(slug: @lyon.slug, s: "qr"), size: 320)
    assert_not_includes response.body, WorkshopQrCode.svg(workshop_link_url(slug: @lyon.slug), size: 320)
  end

  test "the downloadable qr code carries the qr source" do
    sign_in_as users(:printer_lyon)

    get workshop_link_qr_path(format: :svg)

    assert_equal WorkshopQrCode.svg(workshop_link_url(slug: @lyon.slug, s: "qr")), response.body
  end

  test "a named link's qr code carries its own key" do
    channel = @lyon.link_channels.create!(label: "Flyer")
    sign_in_as users(:printer_lyon)

    get workshop_link_qr_path(format: :svg, canal: channel.key)

    assert_equal WorkshopQrCode.svg(workshop_link_url(slug: @lyon.slug, s: "flyer")), response.body
    assert_match(/flyer/, response.headers["Content-Disposition"])
  end

  test "another shop's channel has no qr code here" do
    @rennes.link_channels.create!(label: "Flyer")
    sign_in_as users(:printer_lyon)

    get workshop_link_qr_path(format: :svg, canal: "flyer")

    assert_response :not_found
  end

  # --- Making and removing them -----------------------------------------------------

  test "an Atelier+ shop makes a named link" do
    sign_in_as users(:printer_lyon)

    assert_difference -> { @lyon.link_channels.count }, 1 do
      post workshop_link_channels_path, params: { link_channel: { label: "Salon de Rennes" } }
    end

    assert_redirected_to workshop_link_share_path
    follow_redirect!
    assert_select "input[value=?]", workshop_link_url(slug: @lyon.slug, s: "salon-de-rennes")
    assert_select "a[href=?]", workshop_link_qr_path(format: :svg, canal: "salon-de-rennes")
  end

  test "a shop without Atelier+ cannot make one" do
    sign_in_as users(:printer)

    assert_no_difference -> { WorkshopLinkChannel.count } do
      post workshop_link_channels_path, params: { link_channel: { label: "Flyer" } }
    end
  end

  test "a shop whose Atelier+ lapsed cannot make one" do
    subscriptions(:lyon).update!(status: "canceled")
    sign_in_as users(:printer_lyon)

    assert_no_difference -> { WorkshopLinkChannel.count } do
      post workshop_link_channels_path, params: { link_channel: { label: "Flyer" } }
    end
  end

  test "a bad label is explained, not swallowed" do
    sign_in_as users(:printer_lyon)

    assert_no_difference -> { WorkshopLinkChannel.count } do
      post workshop_link_channels_path, params: { link_channel: { label: "?!" } }
    end

    assert_redirected_to workshop_link_share_path
    assert_predicate flash[:alert], :present?
  end

  test "the eleventh is refused with the reason" do
    WorkshopLinkChannel::LIMIT.times { |n| @lyon.link_channels.create!(label: "Canal #{n}") }
    sign_in_as users(:printer_lyon)

    assert_no_difference -> { WorkshopLinkChannel.count } do
      post workshop_link_channels_path, params: { link_channel: { label: "Un de trop" } }
    end

    assert_match(/#{WorkshopLinkChannel::LIMIT}/, flash[:alert])
  end

  test "a shop deletes its own named link, and the visits it counted stay" do
    channel = @lyon.link_channels.create!(label: "Flyer")
    WorkshopLinkVisit.record!(@lyon, source: channel.key)
    sign_in_as users(:printer_lyon)

    assert_difference -> { WorkshopLinkChannel.count }, -1 do
      delete workshop_link_channel_path(key: channel.key)
    end

    assert_redirected_to workshop_link_share_path
    assert_equal({ "flyer" => 1 }, sources(@lyon))
  end

  test "a shop whose Atelier+ lapsed can still tidy what it made" do
    channel = @lyon.link_channels.create!(label: "Flyer")
    subscriptions(:lyon).update!(status: "canceled")
    sign_in_as users(:printer_lyon)

    get workshop_link_share_path
    assert_select "form[action=?]", workshop_link_channel_path(key: channel.key)
    assert_select "form[action=?]", workshop_link_channels_path, count: 0

    assert_difference -> { WorkshopLinkChannel.count }, -1 do
      delete workshop_link_channel_path(key: channel.key)
    end
  end

  test "a shop cannot delete another shop's named link" do
    channel = @rennes.link_channels.create!(label: "Flyer")
    sign_in_as users(:printer_lyon)

    assert_no_difference -> { WorkshopLinkChannel.count } do
      delete workshop_link_channel_path(key: channel.key)
    end

    assert_response :not_found
  end

  test "only a printer reaches the channel actions" do
    [ :client, :designer, :admin ].each do |role|
      sign_in_as users(role)

      assert_no_difference -> { WorkshopLinkChannel.count } do
        post workshop_link_channels_path, params: { link_channel: { label: "Flyer" } }
      end
      assert_response :redirect, "#{role} must not reach it"

      sign_out
    end
  end

  # --- The screen ---------------------------------------------------------------------

  test "an Atelier+ shop sees where its visits come from" do
    channel = @lyon.link_channels.create!(label: "Salon de Rennes")
    WorkshopLinkVisit.record!(@lyon, source: "qr")
    WorkshopLinkVisit.record!(@lyon, source: channel.key)
    WorkshopLinkVisit.record!(@lyon, source: channel.key)
    sign_in_as users(:printer_lyon)

    get workshop_link_share_path

    assert_select "body", text: /#{Regexp.escape(I18n.t('workshop.links.show.by_source'))}/i
    assert_select "body", text: /Salon de Rennes/
    assert_select "body", text: /#{Regexp.escape(I18n.t('workshop.links.show.source_qr'))}/
  end

  test "a deleted channel's visits are still listed, under their key" do
    WorkshopLinkVisit.record!(@lyon, source: "ancien-flyer")
    sign_in_as users(:printer_lyon)

    get workshop_link_share_path

    assert_select "body", text: /#{Regexp.escape(I18n.t('workshop.links.show.source_removed', key: 'ancien-flyer'))}/
  end

  test "a shop without Atelier+ is not offered the form" do
    sign_in_as users(:printer)

    get workshop_link_share_path

    assert_response :success
    assert_select "form[action=?]", workshop_link_channels_path, count: 0
  end

  private
    def sources(printer) = WorkshopLinkVisit.by_source(printer, days: 30)
end
