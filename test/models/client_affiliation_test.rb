require "test_helper"

class ClientAffiliationTest < ActiveSupport::TestCase
  setup do
    @client = User.create!(email_address: "inconnu@example.invalid", password: "motdepasse-test",
                           first_name: "Paul", last_name: "Inconnu", role: "client",
                           terms_accepted_at: Time.current)
  end

  test "the code admits at once and closes any request still open" do
    ClientAffiliation.request!(client: @client, printer: printers(:lyon))

    ClientAffiliation.admit!(client: @client, printer: printers(:rennes))

    assert_equal printers(:rennes).id, @client.reload.workshop_id
    assert_empty ClientAffiliation.pending.where(client: @client)
  end

  test "asking the shop one already belongs to asks nothing" do
    ClientAffiliation.admit!(client: @client, printer: printers(:rennes))

    assert_nil ClientAffiliation.request!(client: @client, printer: printers(:rennes))
  end

  test "only a client can join a shop" do
    affiliation = ClientAffiliation.new(client: users(:designer), printer: printers(:rennes))

    assert_not affiliation.valid?
  end

  test "the database keeps one open request per client" do
    ClientAffiliation.request!(client: @client, printer: printers(:lyon))

    assert_raises(ActiveRecord::RecordNotUnique) do
      ClientAffiliation.insert!({ client_id: @client.id, printer_id: printers(:rennes).id, status: 0, source: 1,
                                  created_at: Time.current, updated_at: Time.current })
    end
  end

  test "every shop gets its own code, and a new one replaces it" do
    printer = printers(:rennes)
    before = printer.invite_code

    printer.regenerate_invite_code!

    assert_not_equal before, printer.invite_code
    assert printer.invite_code_matches?(printer.invite_code.upcase)
    assert_not printer.invite_code_matches?(before)
    assert_not printer.invite_code_matches?(nil)
  end
end
