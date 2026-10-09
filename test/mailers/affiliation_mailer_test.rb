require "test_helper"

class AffiliationMailerTest < ActionMailer::TestCase
  setup do
    @client = User.create!(email_address: "inconnu@example.invalid", password: "motdepasse-test",
                           first_name: "Paul", last_name: "Inconnu", role: "client",
                           terms_accepted_at: Time.current)
    @affiliation = ClientAffiliation.request!(client: @client, printer: printers(:rennes))
  end

  test "the shop is told who asks, and sent to its space to answer" do
    mail = AffiliationMailer.requested(@affiliation)

    assert_equal [ users(:printer).email_address ], mail.to
    assert_match "Paul Inconnu", mail.subject
    assert_match "inconnu@example.invalid", mail.text_part.body.to_s
    assert_match "/atelier/clients", mail.html_part.body.to_s
  end

  test "the client is told the answer" do
    accepted = AffiliationMailer.accepted(@affiliation)
    declined = AffiliationMailer.declined(@affiliation)

    assert_equal [ @client.email_address ], accepted.to
    assert_match "/designs/nouveau", accepted.text_part.body.to_s
    assert_match "/imprimeurs", declined.text_part.body.to_s
  end

  test "a client taken off a list is told" do
    mail = AffiliationMailer.removed(users(:client), printers(:rennes))

    assert_equal [ users(:client).email_address ], mail.to
    assert_match "Sérigraphie du Thabor", mail.subject
  end
end
