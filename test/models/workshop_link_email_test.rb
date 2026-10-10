require "test_helper"

class WorkshopLinkEmailTest < ActiveSupport::TestCase
  test "the digest recognises an address however it is typed" do
    assert_equal WorkshopLinkEmail.digest("client@example.invalid"), WorkshopLinkEmail.digest("  Client@EXAMPLE.invalid ")
    assert_not_equal WorkshopLinkEmail.digest("client@example.invalid"), WorkshopLinkEmail.digest("autre@example.invalid")
  end

  test "the digest is keyed: a bare hash of the address is not it" do
    assert_not_equal Digest::SHA256.hexdigest("client@example.invalid"), WorkshopLinkEmail.digest("client@example.invalid")
  end

  test "an address is written to once per shop, by the index" do
    digest = WorkshopLinkEmail.digest("client@example.invalid")
    printers(:rennes).link_emails.create!(recipient_digest: digest)

    assert_raises(ActiveRecord::RecordNotUnique) { printers(:rennes).link_emails.create!(recipient_digest: digest) }
  end

  test "today's count is the shop's own, and today's only" do
    rennes = printers(:rennes)
    rennes.link_emails.create!(recipient_digest: "a", created_at: 1.day.ago)
    rennes.link_emails.create!(recipient_digest: "b")
    printers(:lyon).link_emails.create!(recipient_digest: "c")

    assert_equal 1, WorkshopLinkEmail.sent_today(rennes)
  end
end
