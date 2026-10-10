require "test_helper"

# A shop emails its link to a client it already spoke to, and prints its poster
# in its own colours (decided on 10/10/2026).
class WorkshopLinkEmailsTest < ActionDispatch::IntegrationTest
  setup do
    @rennes = printers(:rennes)
  end

  test "a shop sends its link from « Mon lien »" do
    sign_in_as users(:printer)

    get workshop_link_share_path
    assert_select "form[action=?]", workshop_link_emails_path

    assert_enqueued_emails 1 do
      post workshop_link_emails_path, params: { link_email: { email: "client@example.invalid" } }
    end
    assert_redirected_to workshop_link_share_path
    assert_equal "Votre lien est parti à client@example.invalid.", flash[:notice]

    follow_redirect!
    assert_match "1 envoi aujourd&#39;hui", response.body
  end

  test "the same address twice is refused, and said so" do
    sign_in_as users(:printer)
    post workshop_link_emails_path, params: { link_email: { email: "client@example.invalid" } }

    assert_no_enqueued_emails do
      post workshop_link_emails_path, params: { link_email: { email: "client@example.invalid" } }
    end
    assert_equal "Cette adresse a déjà reçu votre lien.", flash[:alert]
  end

  test "only a shop sends its link" do
    sign_in_as users(:client)

    assert_no_enqueued_emails do
      post workshop_link_emails_path, params: { link_email: { email: "client@example.invalid" } }
    end
    assert_response :redirect
    assert_empty WorkshopLinkEmail.all
  end

  # --- The poster ------------------------------------------------------------------

  test "the poster is in the shop's colour and names the platform by its address" do
    @rennes.update_columns(brand_color: "#2B50A8")
    sign_in_as users(:printer)

    get workshop_link_poster_path

    assert_response :success
    assert_match "background-color: #2B50A8; color: #FFFFFF;", response.body
    assert_select "footer", text: /pretatirer\.fr/
    assert_select "h1", text: /Sérigraphie du Thabor/
    assert_select "ol li", count: 5
    assert_match "Besoin d&#39;un graphiste ?", response.body
  end

  test "a named link has its own poster, whose QR code counts apart" do
    channel = @rennes.link_channels.create!(label: "Flyer")
    sign_in_as users(:printer)

    get workshop_link_poster_path(canal: channel.key)

    assert_response :success
    assert_includes response.body,
                    WorkshopQrCode.svg(workshop_invite_url(slug: @rennes.slug, code: @rennes.invite_code, s: "flyer"), size: 196)
    assert_match "Affiche du lien « Flyer »", response.body
  end

  test "another shop's named link has no poster here" do
    channel = printers(:lyon).link_channels.create!(label: "Salon")
    sign_in_as users(:printer)

    get workshop_link_poster_path(canal: channel.key)

    assert_response :not_found
  end
end
