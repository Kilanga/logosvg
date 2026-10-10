require "test_helper"

class WorkshopLinkMailerTest < ActionMailer::TestCase
  setup do
    @rennes = printers(:rennes)
    @rennes.update_columns(brand_color: "#E9B949")
  end

  test "the email comes from the platform in the shop's name, and answers go to the shop" do
    mail = WorkshopLinkMailer.invite(@rennes, "client@example.invalid", nil)

    assert_equal [ "client@example.invalid" ], mail.to
    assert_equal [ "ne-pas-repondre@pretatirer.fr" ], mail.from
    assert_equal "Sérigraphie du Thabor via pretatirer.fr", mail[:from].display_names.first
    assert_equal [ @rennes.orders_email ], mail.reply_to
    assert_match "Sérigraphie du Thabor", mail.subject
  end

  test "it carries the shop's link, counted as email, and its QR code inline" do
    mail = WorkshopLinkMailer.invite(@rennes, "client@example.invalid", nil)
    url = "/a/#{@rennes.slug}/#{@rennes.invite_code}?s=email"

    assert_match url, mail.html_part.body.to_s
    assert_match url, mail.text_part.body.to_s

    qr = mail.attachments["qr.png"]
    assert_predicate qr, :inline?
    assert_match "cid:#{qr.cid}", mail.html_part.body.to_s
  end

  test "it is in the shop's colour, with ink on a pale one" do
    html = WorkshopLinkMailer.invite(@rennes, "client@example.invalid", nil).html_part.body.to_s

    assert_match "background:#E9B949;color:#1D2433", html
  end

  test "the shop's word is shown when written, and escaped" do
    with = WorkshopLinkMailer.invite(@rennes, "client@example.invalid", "Partez sur <b>deux</b> couleurs").html_part.body.to_s
    without = WorkshopLinkMailer.invite(@rennes, "client@example.invalid", nil).html_part.body.to_s

    assert_match "Le mot de l&#39;atelier", with
    assert_match "&lt;b&gt;deux&lt;/b&gt;", with
    assert_no_match "Le mot de l&#39;atelier", without
  end

  test "the platform is named by its address, and promises no further email" do
    mail = WorkshopLinkMailer.invite(@rennes, "client@example.invalid", nil)

    assert_match "pretatirer.fr", mail.text_part.body.to_s
    assert_no_match "Prêt-à-tirer", mail.html_part.body.to_s
    assert_match "Vous ne recevrez pas d&#39;autre", mail.html_part.body.to_s
  end
end
