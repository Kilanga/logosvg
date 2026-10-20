require "test_helper"

# The monthly allowance counts print requests, not generations (decided on
# 20/10/2026). Rennes is on Référencement, Lyon on Atelier+.
class PrinterRequestQuotaTest < ActiveSupport::TestCase
  setup do
    @rennes = printers(:rennes)
    # A clean month: the fixtures' own requests go back to an older one.
    PrintRequest.where(printer: @rennes).update_all(sent_at: 2.months.ago)
  end

  test "the limit comes from the plan, and Atelier+ has none" do
    assert_equal 25, PrinterRequestQuota.for(@rennes).limit
    assert_nil PrinterRequestQuota.for(printers(:lyon)).limit
    assert_nil PrinterRequestQuota.for(nil).limit
    assert_not PrinterRequestQuota.for(printers(:lyon)).reached?
  end

  test "a request counts when the workshop takes it on, not when it arrives" do
    request = new_request

    assert_equal 0, quota.used

    request.acknowledge!
    request.save!

    assert_equal 1, quota.used
  end

  test "every step past acknowledgement still counts" do
    request = new_request
    request.acknowledge!
    request.quote!
    request.start_production!
    request.complete!

    assert_equal 1, quota.used
  end

  test "a request left to expire counts, one the client called off does not" do
    new_request.tap(&:expire!)
    new_request.tap(&:cancel!)

    assert_equal 1, quota.used
  end

  test "declines within the month's share are free, past it they count" do
    requests = Array.new(10) { new_request }
    # A tenth request is a share of three.
    requests.first(3).each(&:decline!)

    assert_equal 0, quota.used
    assert_equal 0, quota.free_declines_left

    requests[3].decline!

    assert_equal 1, quota.used
  end

  test "the share grows as the month's requests come in" do
    requests = Array.new(3) { new_request }

    assert_equal 0, quota.free_declines_left, "three requests leave no free refusal yet"

    requests.concat(Array.new(7) { new_request })

    assert_equal 3, quota.free_declines_left
  end

  test "a request the client called off is no part of the share" do
    Array.new(9) { new_request }
    new_request.tap(&:cancel!)

    assert_equal 2, quota.free_declines_left
  end

  test "a request belongs to the month it was sent in" do
    old = new_request
    old.update_columns(sent_at: 1.month.ago.end_of_month - 1.hour)
    old.acknowledge!

    assert_equal 0, quota.used
  end

  test "another shop's requests are not counted" do
    new_request(printer: printers(:lyon)).tap(&:acknowledge!)

    assert_equal 0, quota.used
  end

  test "the workshop is told once a month, when the allowance is used" do
    Array.new(24) { new_request.tap(&:acknowledge!) }

    assert_enqueued_emails(0) { quota.notify_if_reached! }

    new_request.tap(&:acknowledge!)

    assert_enqueued_email_with SubscriptionMailer, :request_quota_reached, args: [ @rennes ] do
      quota.notify_if_reached!
    end
    assert_enqueued_emails(0) { PrinterRequestQuota.for(@rennes.reload).notify_if_reached! }

    @rennes.update_column(:request_quota_notified_on, 1.month.ago.to_date)
    assert_enqueued_emails(1) { PrinterRequestQuota.for(@rennes.reload).notify_if_reached! }
  end

  test "reaching the allowance is not exceeding it" do
    Array.new(25) { new_request.tap(&:acknowledge!) }

    assert quota.reached?
    assert_not quota.exceeded?
    assert_equal 0, quota.remaining

    new_request.tap(&:acknowledge!)

    assert quota.exceeded?
  end

  test "an unlimited plan is never told" do
    lyon = printers(:lyon)
    Array.new(30) { new_request(printer: lyon).tap(&:acknowledge!) }

    assert_enqueued_emails(0) { PrinterRequestQuota.for(lyon).notify_if_reached! }
  end

  private
    def quota = PrinterRequestQuota.for(@rennes)

    # A copy of a fixture request, sent now, saved as it stands: the quota
    # reads states, not the order's contents.
    def new_request(printer: @rennes)
      request = print_requests(:waiting).dup
      request.assign_attributes(printer: printer, status: "sent", sent_at: Time.current,
                                token: PrintRequest.generate_unique_secure_token,
                                confirmation_token: PrintRequest.generate_unique_secure_token)
      request.save!(validate: false)
      request
    end
end
