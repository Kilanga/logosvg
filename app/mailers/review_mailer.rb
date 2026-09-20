class ReviewMailer < ApplicationMailer
  # A review has just been paid for. Either the chosen designer is told, or
  # every designer who takes that level and can be paid.
  def notify_designers(review)
    @review = review
    recipients = addresses_for(review)
    return message.perform_deliveries = false if recipients.empty?

    # `bcc` rather than `to` when it goes wide: the designers are competing for
    # the same job and have no business seeing each other's addresses.
    if recipients.one?
      mail to: recipients.first, subject: t("mailers.review.notify_designers.subject")
    else
      mail bcc: recipients, to: nil, subject: t("mailers.review.notify_designers.subject")
    end
  end

  def claimed(review)
    @review = review
    mail to: review.client.email_address,
         subject: t("mailers.review.claimed.subject", designer: review.designer_profile.display_name)
  end

  def version_delivered(review, version)
    @review = review
    @version = version
    mail to: review.client.email_address, subject: t("mailers.review.version_delivered.subject")
  end

  def revision_requested(review)
    @review = review
    mail to: review.designer_profile.user.email_address,
         subject: t("mailers.review.revision_requested.subject")
  end

  # The designer handed the job back. What the client needs is the reason, the
  # proposal, the difference in price and the deadline to answer.
  def returned_to_client(review)
    @review = review
    mail to: review.client.email_address, subject: t("mailers.review.returned_to_client.subject")
  end

  def proposal_reminder(review)
    @review = review
    mail to: review.client.email_address, subject: t("mailers.review.proposal_reminder.subject")
  end

  def proposal_expired(review)
    @review = review
    mail to: review.client.email_address, subject: t("mailers.review.proposal_expired.subject")
  end

  # The chosen designer has not taken it in twelve hours; the client chooses
  # what happens next.
  def designer_silent(review)
    @review = review
    mail to: review.client.email_address, subject: t("mailers.review.designer_silent.subject")
  end

  def auto_accepted(review)
    @review = review
    mail to: review.client.email_address, subject: t("mailers.review.auto_accepted.subject")
  end

  def paid(review)
    @review = review
    mail to: review.designer_profile.user.email_address,
         subject: t("mailers.review.paid.subject")
  end

  def refunded(review, amount_cents)
    @review = review
    @amount_cents = amount_cents
    mail to: review.client.email_address, subject: t("mailers.review.refunded.subject")
  end

  # An administrator closed a dispute. Both sides are told, together, with the
  # same account of what was decided.
  def settled_by_admin(review, amount_cents)
    @review = review
    @amount_cents = amount_cents
    recipients = [ review.client.email_address, review.designer_profile&.user&.email_address ].compact

    mail to: recipients, subject: t("mailers.review.settled_by_admin.subject")
  end

  private
    def addresses_for(review)
      if review.chosen? && review.designer_profile
        [ review.designer_profile.user.email_address ]
      else
        DesignerProfile.listed.accepting.offering(review.review_level)
                       .includes(:user).map { |profile| profile.user.email_address }
      end
    end
end
