require "test_helper"

class SendWorkshopLinkTest < ActiveSupport::TestCase
  setup do
    @rennes = printers(:rennes)
  end

  test "the link goes out, and the address is kept only as a digest" do
    assert_enqueued_email_with WorkshopLinkMailer, :invite, args: [ @rennes, "client@example.invalid" ] do
      result = SendWorkshopLink.call(printer: @rennes, email: " Client@Example.invalid ")
      assert_predicate result, :success?
    end

    row = @rennes.link_emails.sole
    assert_equal WorkshopLinkEmail.digest("client@example.invalid"), row.recipient_digest
    assert_not_includes row.recipient_digest, "client"
  end

  test "an address gets the link once from a given shop" do
    SendWorkshopLink.call(printer: @rennes, email: "client@example.invalid")

    assert_no_enqueued_emails do
      assert_equal :already_sent, SendWorkshopLink.call(printer: @rennes, email: "CLIENT@example.invalid").error
    end
  end

  test "another shop may write to the same address" do
    SendWorkshopLink.call(printer: @rennes, email: "client@example.invalid")

    assert_predicate SendWorkshopLink.call(printer: printers(:lyon), email: "client@example.invalid"), :success?
  end

  test "a shop sends so many a day, and again the next day" do
    WorkshopLinkEmail.daily_limit.times do |i|
      @rennes.link_emails.create!(recipient_digest: WorkshopLinkEmail.digest("deja-#{i}@example.invalid"))
    end

    assert_equal :limit_reached, SendWorkshopLink.call(printer: @rennes, email: "un-de-plus@example.invalid").error

    travel 1.day do
      assert_predicate SendWorkshopLink.call(printer: @rennes, email: "un-de-plus@example.invalid"), :success?
    end
  end

  test "a malformed address sends nothing" do
    assert_no_enqueued_emails do
      assert_equal :invalid_email, SendWorkshopLink.call(printer: @rennes, email: "pas-une-adresse").error
    end
    assert_empty @rennes.link_emails
  end

  test "a shop whose link leads nowhere cannot send it" do
    assert_equal :not_listed, SendWorkshopLink.call(printer: printers(:brouillon), email: "client@example.invalid").error
  end
end
