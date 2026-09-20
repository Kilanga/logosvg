# Everything a review does on its own, once nobody has acted.
#
# One recurring job rather than a timer per review: a client who accepts an
# hour after delivery must not leave an auto-acceptance queued for a week. The
# state of the row decides, every time it runs.
class SweepReviewsJob < ApplicationJob
  queue_as :default

  def perform
    expire_proposals
    remind_about_proposals
    warn_about_silent_designers
    auto_accept
  end

  private
    def settings = Rails.application.config.tshirt.reviews

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

    # Seven days after the last delivery with no word from the client, the work
    # is taken as accepted and the designer is paid.
    def auto_accept
      Review.where(status: "delivered")
            .where(delivered_at: ..settings[:auto_accept_days].days.ago)
            .find_each do |review|
        review.accept!
        review.save!
        Payments::SettleReview.call(review: review)
        ReviewMailer.auto_accepted(review).deliver_later
      end
    end
end
