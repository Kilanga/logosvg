require "test_helper"

class WorkshopLinkMailerTest < ActionMailer::TestCase
  setup do
    @rennes = printers(:rennes)
    @rennes.update_columns(brand_color: "#E9B949")
  end

  test "the email comes from the platform in the shop's name, and answers go to the shop" do
    mail = WorkshopLinkMailer.invite(@rennes, "client@example.invalid")

    assert_equal [ "client@example.invalid" ], mail.to
    assert_equal [ "ne-pas-repondre@pretatirer.fr" ], mail.from
    assert_equal "Sérigraphie du Thabor via pretatirer.fr", mail[:from].display_names.first
    assert_equal [ @rennes.orders_email ], mail.reply_to
    assert_match "Sérigraphie du Thabor", mail.subject
  end

  test "it carries the shop's link, counted as email, and its QR code inline" do
    mail = WorkshopLinkMailer.invite(@rennes, "client@example.invalid")
    url = "/a/#{@rennes.slug}/#{@rennes.invite_code}?s=email"

    assert_match url, mail.html_part.body.to_s
    assert_match url, mail.text_part.body.to_s

    qr = mail.attachments["qr.png"]
    assert_predicate qr, :inline?
    assert_match "cid:#{qr.cid}", mail.html_part.body.to_s
  end

  test "it is in the shop's colour, with ink on a pale one" do
    html = WorkshopLinkMailer.invite(@rennes, "client@example.invalid").html_part.body.to_s

    assert_match "background:#E9B949;color:#1D2433", html
  end

  test "it offers the conversion of a ready-made image, and a designer on a quote" do
    html = WorkshopLinkMailer.invite(@rennes, "client@example.invalid").html_part.body.to_s

    assert_match "Vous avez déjà votre visuel ?", html
    assert_match "sur mesure sur devis", html
    assert_no_match "Le mot de l", html
  end

  test "the platform is named by its address, and promises no further email" do
    mail = WorkshopLinkMailer.invite(@rennes, "client@example.invalid")

    assert_match "pretatirer.fr", mail.text_part.body.to_s
    assert_no_match "Prêt-à-tirer", mail.html_part.body.to_s
    assert_match "Vous ne recevrez pas d&#39;autre", mail.html_part.body.to_s
  end
end
