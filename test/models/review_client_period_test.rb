require "test_helper"

# Decided on 09/10/2026: while a review the client ordered is open, their
# thirty days with the shop stand still; a delivery gives thirty fresh days;
# a review that ends without one gives back the time it held.
class ReviewClientPeriodTest < ActiveSupport::TestCase
  setup do
    @client = users(:client)
    Review.where(client: @client).update_all(status: "accepted")
  end

  test "an open review keeps a lapsed client with the shop" do
    @client.update!(workshop_until: 1.minute.ago)
    assert_not User.find(@client.id).attached_to_workshop?

    reviews(:queued).update_column(:status, "queued")

    client = User.find(@client.id)
    assert client.attached_to_workshop?
    assert client.workshop_period_suspended?
    assert_includes User.attached_to(printers(:rennes)), client
  end

  test "an open review on a design made for another shop holds nothing" do
    @client.update!(workshop_until: 1.minute.ago)
    review = reviews(:queued)
    review.update_column(:status, "queued")
    review.design.update_column(:printer_id, printers(:lyon).id)

    assert_not User.find(@client.id).attached_to_workshop?
  end

  test "a delivery gives thirty fresh days" do
    @client.update!(workshop_until: 1.minute.ago)
    review = reviews(:in_progress)
    review.update_column(:status, "in_progress")
    review.design.update_column(:printer_id, printers(:rennes).id)

    review.deliver!

    assert_in_delta 30.days.from_now, @client.reload.workshop_until, 1.minute
  end

  test "a review called off gives back the time it held" do
    @client.update!(workshop_until: 5.days.from_now)
    review = reviews(:queued)
    review.update_columns(status: "queued", paid_at: 2.days.ago)

    review.cancel!

    assert_in_delta 7.days.from_now, @client.reload.workshop_until, 1.minute
  end

  test "a delivery on a design made for another shop gives nothing" do
    @client.update!(workshop_until: 1.minute.ago)
    review = reviews(:in_progress)
    review.update_column(:status, "in_progress")

    review.deliver!

    assert_in_delta 1.minute.ago, @client.reload.workshop_until, 1.minute
  end

  test "an unpaid review called off gives nothing back" do
    @client.update!(workshop_until: 5.days.from_now)
    review = reviews(:queued)
    review.update_columns(status: "awaiting_payment", paid_at: nil, queued_at: nil)

    review.cancel!

    assert_in_delta 5.days.from_now, @client.reload.workshop_until, 1.minute
  end
end
