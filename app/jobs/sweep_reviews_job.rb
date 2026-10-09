# Everything a review does on its own, once nobody has acted.
#
# One recurring job rather than a timer per review: a client who accepts an
# hour after delivery must not leave an auto-acceptance queued for a week. The
# state of the row decides, every time it runs.
class SweepReviewsJob < ApplicationJob
  queue_as :default

  def perform
    release_unclaimed
    expire_proposals
    remind_about_proposals
    warn_about_silent_designers
    remind_before_auto_accept
    auto_accept
  end

  private
    def settings = Rails.application.config.tshirt.reviews

    # Decided on 09/10/2026: a review no designer took within
    # `unclaimed_refund_hours` of going into the queue is called off, and the
    # client gets back everything paid — a custom job, unpaid here, is simply
    # closed. Their thirty days with the shop, held while it was open, run
    # again from where they were.
    def release_unclaimed
      Review.awaiting_claim.where(queued_at: ..settings[:unclaimed_refund_hours].hours.ago).find_each do |review|
        refund = Payments::RefundReview.call(review: review, notify: false) unless review.off_platform?
        # Money that could not go back must not look as if it had: left in the
        # queue, it is tried again on the next run — and stays visible.
        next if refund == :failed

        review.cancel!
        review.save!
        ReviewMailer.unclaimed(review).deliver_later
      end
    end

    # A proposal nobody answered is a refusal, and the client gets their money
    # back. Run before the reminder, so a proposal past its date is not chased
    # and closed in the same minute.
    def expire_proposals
      Review.where(status: "returned_to_client")
            .where(proposal_expires_at: ..Time.current)
            .find_each do |review|
        Payments::RefundReview.call(review: review, amount_cents: review.price_cents)
        review.decline_proposal!
        review.save!
        ReviewMailer.proposal_expired(review).deliver_later
      end
    end

    # Chased once, a day before it lapses.
    def remind_about_proposals
      Review.where(status: "returned_to_client", proposal_reminded_at: nil)
            .where(proposal_expires_at: Time.current..settings[:proposal_reminder_hours].hours.from_now)
            .find_each do |review|
        review.update!(proposal_reminded_at: Time.current)
        ReviewMailer.proposal_reminder(review).deliver_later
      end
    end

    # The designer the client picked has had twelve hours. The client decides
    # what happens next — this only tells them the choice exists.
    def warn_about_silent_designers
      Review.awaiting_claim.where(assignment_mode: "chosen")
            .where.not(designer_profile_id: nil)
            .where(paid_at: ..settings[:designer_claim_timeout_hours].hours.ago)
            .where(designer_reminded_at: nil)
            .find_each do |review|
        review.update!(designer_reminded_at: Time.current)
        ReviewMailer.designer_silent(review).deliver_later
      end
    end

    # Decided on 08/10/2026: a client who missed the delivery email must not
    # find out a week later that silence counted as a yes. Told three days,
    # then one day, before it does — each reminder once per delivery, and
    # never one that is already late: a sweep that missed a run sends the
    # closest reminder only.
    def remind_before_auto_accept
      days = settings[:auto_accept_days]
      reminders = Array(settings[:acceptance_reminder_days]).map(&:to_i).sort.reverse

      # Closest first: a review that already earned the last reminder is
      # marked past the earlier ones, which then leave it alone.
      reminders.each_with_index.reverse_each do |days_left, index|
        Review.where(status: "delivered", acceptance_reminders_sent: ...(index + 1))
              .where(delivered_at: ..(days - days_left).days.ago)
              .where(delivered_at: (days.days.ago + 1.minute)..)
              .find_each do |review|
          review.update!(acceptance_reminders_sent: index + 1)
          ReviewMailer.acceptance_reminder(review, days_left).deliver_later
        end
      end
    end

    # Seven days after the last delivery with no word from the client, the work
    # is taken as accepted and the designer is paid.
    def auto_accept
      Review.where(status: "delivered")
            .where(delivered_at: ..settings[:auto_accept_days].days.ago)
            .find_each do |review|
        review.accept!
        review.save!
        Payments::SettleReview.call(review: review)
        CreateReviewedDesign.call(review: review)
        ReviewMailer.auto_accepted(review).deliver_later
      end
    end
end
