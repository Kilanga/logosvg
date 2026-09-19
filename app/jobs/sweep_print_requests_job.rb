# Chases the workshops that have not answered, and closes the requests nobody
# ever will.
#
# One recurring job rather than two timers per request: a request that is
# acknowledged an hour after it was sent must not leave a reminder queued for
# the next two days. The state of the row decides, every time it runs.
class SweepPrintRequestsJob < ApplicationJob
  queue_as :default

  # Expiry first, deliberately. A request old enough to expire is also old
  # enough to be chased, and chasing it before closing it would send the
  # workshop a reminder and the client a closure in the same minute. Expiring
  # takes it out of `awaiting_acknowledgement`, so the reminder never fires.
  def perform
    expire
    remind
  end

  private
    def settings = Rails.application.config.tshirt.print_requests

    # Nothing after 48 hours: the workshop is chased once, and once only —
    # `reminded_at` is what stops this from running every time the sweep does.
    def remind
      PrintRequest.awaiting_acknowledgement
                  .where(reminded_at: nil)
                  .where(sent_at: ..settings[:reminder_after_hours].hours.ago)
                  .find_each do |print_request|
        print_request.update!(reminded_at: Time.current)
        PrintRequestMailer.reminder(print_request).deliver_later
      end
    end

    # After five days the client is told to choose another workshop, rather than
    # left waiting on a shop that never looked.
    def expire
      PrintRequest.awaiting_acknowledgement
                  .where(sent_at: ..settings[:expire_after_days].days.ago)
                  .find_each do |print_request|
        print_request.expire!
        print_request.save!
        PrintRequestMailer.expired(print_request).deliver_later
      end
    end
end
