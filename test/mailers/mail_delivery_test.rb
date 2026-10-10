require "test_helper"

# The site's emails against the Brevo plan (decided on 10/10/2026): each one
# counted per recipient, retried when the relay refuses, answered to a
# mailbox someone reads.
class MailDeliveryTest < ActionMailer::TestCase
  include ActiveJob::TestHelper

  # A relay that refuses, the way Brevo would.
  class RefusingDelivery
    cattr_accessor :error

    def initialize(_settings) = nil

    def deliver!(_message) = raise(error)
  end

  ActionMailer::Base.add_delivery_method :refusing, RefusingDelivery

  test "every email is counted per recipient" do
    PasswordsMailer.reset(users(:client)).deliver_now
    ReviewMailer.claimed(reviews(:in_progress)).deliver_now

    expected = 1 + [ ActionMailer::Base.deliveries.last.to, ActionMailer::Base.deliveries.last.cc ].flatten.compact.uniq.size
    assert_equal expected, MailDeliveryDay.today.recipients_count
  end

  test "an answer goes to the site's contact address, unless the email says otherwise" do
    reset = PasswordsMailer.reset(users(:client))
    to_printer = PrintRequestMailer.to_printer(print_requests(:waiting))

    assert_equal [ Rails.application.config.tshirt.support_email ], reset.reply_to
    assert_not_equal [ Rails.application.config.tshirt.support_email ], to_printer.reply_to
  end

  test "emails are delivered by the retrying job" do
    assert_equal MailDeliveryJob, ApplicationMailer.delivery_job
  end

  test "a busy relay or a spent quota is tried again later" do
    [ Net::SMTPServerBusy.new("421 try again later"),
      Net::SMTPFatalError.new("550 daily sending limit reached") ].each do |error|
      with_refusing_relay(error) do
        assert_enqueued_with(job: MailDeliveryJob) { reset_job.perform_now }
      end
      clear_enqueued_jobs
    end

    assert_equal 0, MailDeliveryDay.today.failed_count
  end

  test "an email refused for good is counted as failed" do
    with_refusing_relay(Net::SMTPFatalError.new("550 mailbox unavailable")) do
      assert_raises(Net::SMTPFatalError) { reset_job.perform_now }
    end

    assert_equal 1, MailDeliveryDay.today.failed_count
  end

  private
    # The job `deliver_later` would enqueue, run here and now: its retries are
    # what is under test.
    def reset_job = MailDeliveryJob.new("PasswordsMailer", "reset", "deliver_now", args: [ users(:client) ])

    def with_refusing_relay(error)
      RefusingDelivery.error = error
      previous = ApplicationMailer.delivery_method
      ApplicationMailer.delivery_method = :refusing
      yield
    ensure
      ApplicationMailer.delivery_method = previous
    end
end
