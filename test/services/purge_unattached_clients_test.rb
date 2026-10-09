require "test_helper"

class PurgeUnattachedClientsTest < ActiveSupport::TestCase
  setup do
    @leftover = User.create!(email_address: "ancien-test@example.invalid", password: "motdepasse-test",
                             first_name: "Ancien", last_name: "Test", role: "client",
                             terms_accepted_at: Time.current)
    @design = Design.create!(user: @leftover, prompt: "un renard", technique: "screen_printing",
                             style: "illustration", print_width_cm: 25, status: "ready")
    @waiting = User.create!(email_address: "en-attente@example.invalid", password: "motdepasse-test",
                            first_name: "En", last_name: "Attente", role: "client",
                            terms_accepted_at: Time.current)
    ClientAffiliation.request!(client: @waiting, printer: printers(:lyon))
  end

  test "without confirmation, it lists and deletes nothing" do
    summary = nil

    assert_no_difference -> { User.count } do
      summary = PurgeUnattachedClients.call(io: StringIO.new)
    end

    assert_includes summary.clients, @leftover.email_address
    assert_equal 1 + Design.where(user: User.client.where(workshop_id: nil)).where.not(user: @leftover).count,
                 summary.designs
  end

  test "it deletes clients with no shop and what they made, and keeps the others" do
    unattached = User.client.where(workshop_id: nil).where.not(id: @waiting.id).pluck(:id)
    professionals = User.where.not(role: "client").count

    PurgeUnattachedClients.call(confirm: true, io: StringIO.new)

    assert_empty User.where(id: unattached)
    assert_not Design.exists?(@design.id)
    assert User.exists?(@waiting.id), "a client waiting on a shop is a new account, not a leftover"
    assert User.exists?(users(:client).id), "a client with a shop is kept"
    assert_equal professionals, User.where.not(role: "client").count
  end
end
