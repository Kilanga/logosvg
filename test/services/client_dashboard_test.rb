require "test_helper"

# What the dashboard puts first is a business rule, not a layout choice.
class ClientDashboardTest < ActiveSupport::TestCase
  test "a failed generation is offered to be retried" do
    designs(:pending_design).fail!("le service n'a pas répondu")
    designs(:pending_design).save!

    assert_includes kinds, :design_failed
  end

  # The whole point of the platform, left undone. Both fixture designs have
  # been sent already, so one is freed first.
  test "a finished design nobody was asked to print is brought forward" do
    assert_not_includes unsent, designs(:fox_dtf), "it has a request to begin with"

    designs(:fox_dtf).print_requests.destroy_all

    assert_includes unsent, designs(:fox_dtf)
  end

  test "a design already sent to a workshop is not brought forward" do
    assert_not_includes unsent, designs(:fox_screen),
                        "that one has a print request already"
  end

  # A request that came to nothing leaves the design needing a workshop again.
  test "a design whose only request expired is brought forward again" do
    designs(:fox_dtf).print_requests.each { |r| r.expire! if r.may_expire? }

    assert_not_includes unsent, designs(:fox_dtf),
                        "an expired request is still a request on the record"
  end

  # Worth saying before the sweep expires it.
  test "a workshop that has not confirmed for two days is flagged" do
    silent = actions.select { |a| a.kind == :print_request_silent }.map(&:record)

    assert_includes silent, print_requests(:forgotten)
  end

  test "a request sent an hour ago is not yet a problem" do
    silent = actions.select { |a| a.kind == :print_request_silent }.map(&:record)

    assert_not_includes silent, print_requests(:waiting)
  end

  test "a request the workshop acknowledged is never flagged" do
    print_requests(:forgotten).acknowledge!
    print_requests(:forgotten).save!

    silent = actions.select { |a| a.kind == :print_request_silent }.map(&:record)

    assert_not_includes silent, print_requests(:forgotten)
  end

  # Paid for and done: validating it is the one step left. See docs/SPEC.md,
  # "Espace client".
  test "a delivered review is offered for validation" do
    delivered = actions.select { |a| a.kind == :review_delivered }.map(&:record)

    assert_includes delivered, reviews(:delivered)
  end

  test "a review still in progress is not offered for validation" do
    delivered = actions.select { |a| a.kind == :review_delivered }.map(&:record)

    assert_not_includes delivered, reviews(:in_progress)
  end

  test "a returned review with an open proposal is brought forward" do
    proposals = actions.select { |a| a.kind == :review_proposal }.map(&:record)

    assert_includes proposals, reviews(:returned)
  end

  test "a returned review whose proposal has expired is not brought forward" do
    reviews(:returned).update!(proposal_expires_at: 1.hour.ago)
    proposals = actions.select { |a| a.kind == :review_proposal }.map(&:record)

    assert_not_includes proposals, reviews(:returned)
  end

  test "the most recent thing to act on comes first" do
    dates = actions.map(&:on)

    assert_equal dates.sort.reverse, dates
  end

  # Another client's work is another client's business.
  test "nothing from another account reaches the dashboard" do
    data = ClientDashboard.call(client: users(:deleted_client))

    assert_not_includes data[:designs], designs(:fox_screen)
    assert_empty data[:actions].select { |a| a.record == print_requests(:waiting) }
  end

  test "a soft-deleted design leaves the lists entirely" do
    designs(:fox_dtf).soft_delete!

    assert_not_includes ClientDashboard.call(client: users(:client))[:designs],
                        designs(:fox_dtf)
    assert_empty actions.select { |a| a.record == designs(:fox_dtf) }
  end

  # Reported on 14/10/2026: one idea retouched gave two « Design prêt, jamais
  # envoyé » and several entries in « Derniers designs ».
  test "a retouched idea counts once, by its newest version" do
    client = users(:client)
    root = designs(:fox_screen)
    PrintRequest.where(design_id: root.id).delete_all
    Review.where(design_id: root.id).delete_all
    child = Design.create!(root.attributes.except("id", "token", "created_at", "updated_at", "batch_token", "chosen_at")
                               .merge("parent_id" => root.id, "root_id" => root.id, "status" => "ready"))

    dashboard = ClientDashboard.call(client: client)

    unsent = dashboard[:actions].select { |a| a.kind == :design_unsent }.map(&:record)
    assert_includes unsent.map(&:id), child.id
    assert_not_includes unsent.map(&:id), root.id

    lineage_entries = dashboard[:designs].select { |d| (d.root_id || d.id) == root.id }
    assert_equal [ child.id ], lineage_entries.map(&:id)
  end

  test "an idea sent from any of its versions is no longer waiting" do
    root = designs(:fox_screen)
    assert PrintRequest.exists?(design_id: root.id)
    Design.create!(root.attributes.except("id", "token", "created_at", "updated_at", "batch_token", "chosen_at")
                       .merge("parent_id" => root.id, "root_id" => root.id, "status" => "ready"))

    unsent = ClientDashboard.call(client: users(:client))[:actions].select { |a| a.kind == :design_unsent }

    assert(unsent.none? { |a| (a.record.root_id || a.record.id) == root.id })
  end

  # Reported on 17/10/2026 (H4): three proposals drawn and none kept, and
  # the dashboard said nothing had been created.
  test "a click whose proposals are still to choose is brought forward once" do
    root = designs(:fox_screen)
    attrs = root.attributes.except("id", "token", "created_at", "updated_at", "chosen_at", "root_id", "parent_id")
    proposals = Array.new(3) { Design.create!(attrs.merge("batch_token" => "lot-h4", "status" => "ready")) }

    waiting = actions.select { |a| a.kind == :proposals_to_choose }
    assert_equal 1, waiting.size
    assert_includes proposals.map(&:id), waiting.first.record.id

    proposals.first.update!(chosen_at: Time.current)
    assert_not_includes kinds, :proposals_to_choose, "a kept proposal is a design, not a choice"
  end

  private
    def actions = ClientDashboard.call(client: users(:client))[:actions]

    def kinds = actions.map(&:kind)

    def unsent = actions.select { |a| a.kind == :design_unsent }.map(&:record)
end
