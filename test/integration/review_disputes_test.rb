require "test_helper"

# Decided on 08/10/2026: the client can say a delivery does not do what was
# asked; the designer can offer a free fix; an administrator can split.
class ReviewDisputesTest < ActionDispatch::IntegrationTest
  setup { @review = reviews(:delivered) }

  test "a client signals a problem: the clock stops and both are told" do
    sign_in_as users(:client)

    assert_emails 1 do
      post dispute_review_path(@review),
           params: { reason: "not_as_requested", dispute_message: "Le texte demandé n'apparaît pas." }
      perform_enqueued_jobs
    end

    @review.reload
    assert_predicate @review, :disputed?
    assert_equal "not_as_requested", @review.dispute_reason
    assert_equal "Le texte demandé n'apparaît pas.", @review.messages.last.body

    mail = ActionMailer::Base.deliveries.last
    assert_includes mail.to, users(:designer).email_address
    assert_includes mail.bcc, users(:admin).email_address
  end

  test "a signal without an explanation is refused" do
    sign_in_as users(:client)

    post dispute_review_path(@review), params: { reason: "other", dispute_message: "Non." }

    assert_predicate @review.reload, :delivered?
    assert_equal I18n.t("reviews.dispute.errors.message"), flash[:alert]
  end

  test "nobody else can signal a review" do
    sign_in_as users(:designer)

    post dispute_review_path(@review), params: { reason: "other", dispute_message: "Je signale pour lui." }

    assert_predicate @review.reload, :delivered?
  end

  test "a disputed review is not accepted automatically" do
    @review.update!(delivered_at: 8.days.ago)
    @review.dispute!
    @review.save!

    SweepReviewsJob.perform_now

    assert_predicate @review.reload, :disputed?
  end

  test "the designer offers a fix, the client takes it, and the work restarts" do
    @review.dispute!
    @review.save!

    sign_in_as users(:designer)
    post offer_fix_designer_review_path(@review), params: { fix_message: "Je reprends le texte, sans frais." }
    assert_not_nil @review.reload.fix_offered_at

    sign_in_as users(:client)
    get review_path(@review)
    assert_select "form[action=?]", accept_fix_review_path(@review)

    post accept_fix_review_path(@review)

    assert_predicate @review.reload, :in_progress?
  end

  test "the client may withdraw and get a fresh week" do
    @review.update!(delivered_at: 5.days.ago)
    @review.dispute!
    @review.save!
    sign_in_as users(:client)

    post withdraw_dispute_review_path(@review)

    assert_predicate @review.reload, :delivered?
    assert @review.delivered_at > 1.minute.ago
  end

  test "the delivery screen offers the signal, once" do
    sign_in_as users(:client)

    get review_path(@review)
    assert_select "form[action=?]", dispute_review_path(@review)

    @review.dispute!
    @review.withdraw_dispute!
    @review.save!

    get review_path(@review)
    assert_select "form[action=?]", dispute_review_path(@review), count: 0
  end

  # --- The administration ---------------------------------------------------

  test "an administrator splits: part refunded, the designer paid for the rest" do
    ENV["STRIPE_SECRET_KEY"] = "sk_test_not_a_real_key_placeholder"
    stub_request(:post, %r{/v1/refunds}).to_return(
      headers: { "Content-Type" => "application/json" }, body: { id: "re_1" }.to_json
    )
    stub_request(:get, %r{/v1/payment_intents/}).to_return(
      headers: { "Content-Type" => "application/json" },
      body: { id: "pi_test_delivered", latest_charge: "ch_1", amount_received: 1900 }.to_json
    )
    transfer = stub_request(:post, %r{/v1/transfers})
               .with { |request| Rack::Utils.parse_nested_query(request.body)["amount"] == "800" }
               .to_return(headers: { "Content-Type" => "application/json" }, body: { id: "tr_1" }.to_json)
    deliver_a_version
    @review.dispute!
    @review.save!
    sign_in_as users(:admin)

    post settle_admin_review_path(@review),
         params: { decision: "split", refund: "9", note: "Texte manquant, travail fait pour le reste." }

    @review.reload
    assert_predicate @review, :accepted?
    assert_equal 900, @review.refunded_cents
    assert_equal 800, @review.designer_payout_cents
    assert_requested transfer
  ensure
    ENV.delete("STRIPE_SECRET_KEY")
  end

  test "splitting needs a delivered version" do
    @review.dispute!
    @review.save!
    sign_in_as users(:admin)

    post settle_admin_review_path(@review), params: { decision: "split", refund: "0", note: "Payer." }

    assert_predicate @review.reload, :disputed?
    assert_equal I18n.t("admin.disputes.errors.nothing_delivered"), flash[:alert]
  end

  test "a client's signal is listed among the reviews to settle" do
    @review.dispute!
    @review.save!
    sign_in_as users(:admin)

    get admin_reviews_path(filtre: "disputed")

    assert_select "a[href=?]", admin_review_path(@review)
  end

  test "a designer who keeps losing disputes is flagged to the administration" do
    2.times do
      Review.create!(design: designs(:fox_screen), client: users(:client), review_level: review_levels(:check),
                     designer_profile: designer_profiles(:ines), client_brief: "x", price_cents: 1900,
                     platform_fee_cents: 380, status: "canceled", disputed_at: 3.days.ago,
                     settled_at: 1.day.ago, refunded_cents: 1900)
    end
    sign_in_as users(:admin)

    get admin_dashboard_path

    assert_select "h2", text: /#{I18n.t("admin.dashboards.show.lost_disputes")}/i
  end

  private
    def deliver_a_version
      @review.versions.create!(file: { io: StringIO.new(%(<svg xmlns="http://www.w3.org/2000/svg"/>)),
                                       filename: "v.svg", content_type: "image/svg+xml" })
    end
end
