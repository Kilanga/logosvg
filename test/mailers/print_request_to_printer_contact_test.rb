require "test_helper"

# Asked on 14/10/2026: the workshop's email says how to reach the client, by
# email and by telephone, without going back to the site.
class PrintRequestToPrinterContactTest < ActionMailer::TestCase
  test "the workshop's email gives the client's email and telephone" do
    request = print_requests(:waiting)
    request.update_columns(contact_phone: "+33612345678")

    mail = PrintRequestMailer.to_printer(request)

    [ mail.html_part.body.to_s, mail.text_part.body.to_s ].each do |body|
      assert_includes body, I18n.t("mailers.print_request.to_printer.contact_title")
      assert_includes body, request.contact_email
      assert_includes body, "+33612345678"
    end
    assert_includes mail.html_part.body.to_s, "tel:+33612345678"
  end
end
