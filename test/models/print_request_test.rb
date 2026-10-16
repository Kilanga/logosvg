require "test_helper"

# The state machine, transition by transition — including the ones that must not
# happen. See docs/SPEC.md, "Demande d'impression".
class PrintRequestStateMachineTest < ActiveSupport::TestCase
  test "a request starts sent: it exists because it was sent" do
    assert_predicate PrintRequest.new, :sent?
  end

  test "sent is acknowledged, and the moment is kept" do
    request = print_requests(:waiting)

    assert request.may_acknowledge?
    request.acknowledge!

    assert_predicate request, :acknowledged?
    assert_not_nil request.acknowledged_at
  end

  # The timestamp is what the workshop's list sorts and the client's rail
  # reads: it has to survive the save, not only live in memory.
  test "the moment of acknowledgement reaches the database" do
    request = print_requests(:waiting)
    request.acknowledge!
    request.save!

    assert_not_nil request.reload.acknowledged_at
  end

  test "the one step a workshop can take is the next one, and only that" do
    request = print_requests(:waiting)

    assert_equal :acknowledge, request.next_workshop_event

    request.acknowledge!

    assert_equal :quote, request.next_workshop_event

    request.quote!

    assert_equal :start_production, request.next_workshop_event
  end

  test "a closed request offers the workshop nothing" do
    assert_nil print_requests(:waiting).tap(&:cancel!).next_workshop_event
    assert_nil print_requests(:forgotten).tap(&:expire!).next_workshop_event
  end

  test "acknowledged is quoted, and the moment is kept" do
    request = print_requests(:acknowledged)

    assert request.may_quote?
    request.quote!

    assert_predicate request, :quoted?
    assert_not_nil request.quoted_at
  end

  test "the workshop walks the whole way through" do
    request = print_requests(:waiting)

    request.acknowledge!
    request.quote!
    request.start_production!

    assert_predicate request, :in_production?

    request.complete!

    assert_predicate request, :completed?
  end

  test "a client calls off a request the shop has not begun" do
    [ :waiting, :acknowledged ].each do |fixture|
      request = print_requests(fixture)

      assert request.may_cancel?
      request.cancel!

      assert_predicate request, :canceled?
    end
  end

  test "a request already in production is no longer the client's to cancel" do
    request = print_requests(:waiting).tap { |r| r.acknowledge!; r.quote!; r.start_production! }

    assert_not request.may_cancel?
    assert_raises(AASM::InvalidTransition) { request.cancel! }
  end

  # Only a request the shop never looked at expires.
  test "expiry reaches a request that was never acknowledged, and nothing else" do
    waiting = print_requests(:waiting)

    assert waiting.may_expire?
    waiting.expire!

    assert_predicate waiting, :expired?

    acknowledged = print_requests(:acknowledged)

    assert_not acknowledged.may_expire?
    assert_raises(AASM::InvalidTransition) { acknowledged.expire! }
  end

  test "a request cannot be quoted before it is acknowledged" do
    request = print_requests(:waiting)

    assert_not request.may_quote?
    assert_raises(AASM::InvalidTransition) { request.quote! }
  end

  test "a request cannot go into production before a quote" do
    request = print_requests(:acknowledged)

    assert_not request.may_start_production?
    assert_raises(AASM::InvalidTransition) { request.start_production! }
  end

  test "a request cannot be acknowledged twice" do
    request = print_requests(:acknowledged)

    assert_not request.may_acknowledge?
    assert_raises(AASM::InvalidTransition) { request.acknowledge! }
  end

  test "a canceled request is an end, not a step" do
    request = print_requests(:waiting).tap(&:cancel!)

    assert_not request.may_acknowledge?
    assert_not request.may_quote?
    assert_not request.may_expire?

    assert_raises(AASM::InvalidTransition) { request.acknowledge! }
    assert_raises(AASM::InvalidTransition) { request.expire! }
  end

  test "an expired request is an end too" do
    request = print_requests(:waiting).tap(&:expire!)

    assert_not request.may_acknowledge?
    assert_not request.may_cancel?

    assert_raises(AASM::InvalidTransition) { request.acknowledge! }
    assert_raises(AASM::InvalidTransition) { request.cancel! }
  end

  test "a completed request never moves again" do
    request = print_requests(:waiting)
    request.acknowledge!
    request.quote!
    request.start_production!
    request.complete!

    assert_not request.may_cancel?
    assert_not request.may_start_production?
    assert_raises(AASM::InvalidTransition) { request.cancel! }
  end
end

class PrintRequestTest < ActiveSupport::TestCase
  test "public urls carry the token, never the id" do
    request = print_requests(:waiting)

    assert_equal request.token, request.to_param
    assert_not_equal request.id.to_s, request.to_param
  end

  test "the total is counted from the sizes, never trusted from the form" do
    request = build_request(sizes: { "M" => "4", "L" => "6" }, total_qty: 999)

    assert_predicate request, :valid?
    assert_equal 10, request.total_qty
  end

  test "a request with no garment in it is not a job" do
    request = build_request(sizes: { "M" => "0" })

    assert_not request.valid?
    assert request.errors.include?(:sizes)
  end

  test "a size the catalogue does not know is refused" do
    request = build_request(sizes: { "XXXXL" => "2" })

    assert_not request.valid?
    assert request.errors.include?(:sizes)
  end

  # The shop published a minimum; a request under it would be quoted "no".
  # `rennes` asks for twenty.
  test "a run below the shop's minimum is refused" do
    request = build_request(printer: printers(:rennes), sizes: { "M" => "5" })

    assert_not request.valid?
    assert request.errors.include?(:sizes)
  end

  test "a run that reaches the shop's minimum passes" do
    assert_predicate build_request(printer: printers(:rennes), sizes: { "M" => "20" }), :valid?
  end

  # The minimum judges the request as it was sent. A shop that raises it next
  # month must not strand a job already in its hands.
  test "a shop raising its minimum does not freeze the requests it already has" do
    request = print_requests(:waiting)
    request.printer.update!(min_order_qty: 500)

    assert request.acknowledge!, "the workshop can still move it along"
    assert_predicate request.reload, :acknowledged?
  end

  # Same reasoning: a desired date simply arrives.
  test "a desired date going by does not freeze the request" do
    request = print_requests(:waiting)
    request.update_column(:desired_on, Date.yesterday)

    assert request.acknowledge!
    assert_predicate request.reload, :acknowledged?
  end

  test "a date already gone is refused" do
    assert_not build_request(desired_on: Date.yesterday).valid?
    assert_predicate build_request(desired_on: Date.tomorrow), :valid?
  end

  # The consent is what allows the client's details to reach the workshop.
  test "a request without consent does not leave" do
    request = build_request(consented_at: nil, consent_text_version: nil)

    assert_not request.valid?
    assert request.errors.of_kind?(:base, :no_consent)
    # One message for one box, in words (reported on 14/10/2026).
    assert_equal [ I18n.t("activerecord.errors.models.print_request.attributes.base.no_consent") ],
                 request.errors.full_messages
  end

  test "a request needs someone to answer" do
    assert_not build_request(contact_name: "").valid?
    # Reported on 17/10/2026: a request reached the workshop with no telephone.
    assert_not build_request(contact_phone: "").valid?
    assert_not build_request(contact_email: "").valid?
    assert_not build_request(contact_email: "pas-une-adresse").valid?
  end

  test "sizes come back in the catalogue's order, not the order they were typed" do
    request = build_request(sizes: { "XL" => "1", "S" => "2", "M" => "3" })

    assert_equal [ [ "S", 2 ], [ "M", 3 ], [ "XL", 1 ] ], request.ordered_sizes
  end

  test "a size left empty is not carried into the order" do
    request = build_request(sizes: { "S" => "2", "M" => "", "L" => "0" })

    assert_equal [ [ "S", 2 ] ], request.ordered_sizes
  end

  # A mail scanner following an old link must not revive anything.
  test "a confirmation link is dead once the request has moved on" do
    assert_predicate print_requests(:waiting), :confirmable?
    assert_not_predicate print_requests(:acknowledged), :confirmable?
    assert_not_predicate print_requests(:waiting).tap(&:cancel!), :confirmable?
  end

  test "a confirmation link expires with time as well as with state" do
    request = print_requests(:waiting)
    request.update!(sent_at: 40.days.ago)

    assert_predicate request, :confirmation_expired?
    assert_not_predicate request, :confirmable?
  end

  test "a request is chased once, and only once" do
    forgotten = print_requests(:forgotten)

    assert_includes PrintRequest.reminder_due, forgotten

    forgotten.update!(reminded_at: Time.current)

    assert_not_includes PrintRequest.reminder_due, forgotten
  end

  test "a request just sent is neither chased nor expired" do
    waiting = print_requests(:waiting)

    assert_not_includes PrintRequest.reminder_due, waiting
    assert_not_includes PrintRequest.expiry_due, waiting
  end

  test "a request left long enough is due to expire" do
    assert_includes PrintRequest.expiry_due, print_requests(:forgotten)
  end

  # --- Only what the shop offers (decided on 16/10/2026) -------------------

  test "a shop doing both lets the client choose how the order comes back" do
    printers(:nantes).update!(pickup: true, ships: true)

    assert_predicate build_request(delivery_method: "shipping"), :valid?
    assert_predicate build_request(delivery_method: "pickup"), :valid?

    request = build_request
    assert_not request.valid?
    assert request.errors.of_kind?(:delivery_method, :blank)
  end

  test "a shop doing only one way has it chosen for the client" do
    printers(:nantes).update!(pickup: true, ships: false)

    request = build_request
    assert_predicate request, :valid?
    assert_equal "pickup", request.delivery_method
  end

  test "a way the shop does not offer is refused" do
    printers(:nantes).update!(pickup: true, ships: false)

    assert build_request(delivery_method: "shipping").tap(&:valid?).errors.of_kind?(:delivery_method, :not_offered)
  end

  test "express only where the shop offers it" do
    assert_predicate build_request(express: true), :valid?, "nantes offers express"

    printers(:nantes).update!(express_available: false)
    assert build_request(express: true).tap(&:valid?).errors.of_kind?(:express, :not_offered)
  end

  test "a textile source and a placement the shop does not offer are refused" do
    printers(:nantes).update!(provides_textile: true, accepts_client_textile: false, placements: [ "chest_center" ])

    request = build_request(textile_source: "client", placements: [ "back_full" ])
    assert_not request.valid?
    assert request.errors.of_kind?(:textile_source, :not_offered)
    assert request.errors.of_kind?(:placements, :not_offered)
  end

  private
    # `nantes` publishes no minimum order, so a test that is not about the
    # minimum is not silently about it.
    def build_request(**attributes)
      PrintRequest.new({
        design: designs(:fox_screen),
        client: users(:client),
        printer: printers(:nantes),
        print_width_cm: 25,
        sizes: { "M" => "5" },
        contact_name: "Claire Martin", contact_phone: "0612345678",
        contact_email: "claire@example.invalid",
        consent_text_version: "2026-09-v1",
        consented_at: Time.current
      }.merge(attributes))
    end
end
