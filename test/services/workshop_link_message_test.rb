require "test_helper"

class WorkshopLinkMessageTest < ActiveSupport::TestCase
  setup do
    @rennes = printers(:rennes)
    @url = "https://pretatirer.fr/a/#{@rennes.slug}/#{@rennes.invite_code}?s=email"
  end

  test "the message carries the shop's link, its name and the platform's services" do
    body = WorkshopLinkMessage.new(@rennes, url: @url).body

    assert_includes body, @url
    assert body.start_with?("Bonjour,")
    assert body.end_with?(@rennes.name)
    assert_includes body, "Besoin d'un graphiste ?"
    assert_includes body, "3 propositions"
  end

  test "the shop's own text comes after the greeting, when it wrote one" do
    without = WorkshopLinkMessage.new(@rennes, url: @url).body
    @rennes.link_email_note = "Passez nous voir le samedi."
    with = WorkshopLinkMessage.new(@rennes, url: @url).body

    assert_not_includes without, "Passez nous voir"
    assert_operator with.index("Passez nous voir"), :<, with.index(@url)
  end

  test "the mailto link opens a message with no recipient, spaces encoded as %20" do
    message = WorkshopLinkMessage.new(@rennes, url: @url)
    mailto = message.mailto

    assert mailto.start_with?("mailto:?subject=")
    assert_not_includes mailto, "+"
    assert_equal message.body, CGI.unescape(mailto[/body=(.*)\z/, 1].gsub("+", "%2B"))
    assert_includes CGI.unescape(mailto[/subject=([^&]*)/, 1]), @rennes.name
  end

  test "the message stays short enough for every mail app" do
    @rennes.link_email_note = "x" * Printer::LINK_EMAIL_NOTE_MAX

    assert_operator WorkshopLinkMessage.new(@rennes, url: @url).mailto.length, :<, 4000
  end
end
