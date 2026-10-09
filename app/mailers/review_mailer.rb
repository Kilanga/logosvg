class ReviewMailer < ApplicationMailer
  # A review has just been paid for. Either the chosen designer is told, or
  # every designer who takes that level and can be paid.
  def notify_designers(review)
    review = @review = reload(review)
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
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: review.client.email_address,
         subject: t("mailers.review.claimed.subject", designer: review.designer_profile.display_name)
  end

  # A custom job, just taken: the designer gets the client's details to quote
  # and arrange it directly. Only now, and only to the designer who took it —
  # with the client's workshop in copy, which the client was told when asking.
  def client_contact(review)
    review = @review = reload(review)
    @client = @review.client
    mail cc: shop_copy(review),
         to: @review.designer_profile.user.email_address,
         reply_to: @client.email_address,
         subject: t("mailers.review.client_contact.subject", client: @client.full_name)
  end

  def finished_off_platform(review)
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: @review.client.email_address, subject: t("mailers.review.finished_off_platform.subject")
  end

  def version_delivered(review, version)
    review = @review = reload(review)
    @version = version
    mail cc: shop_copy(review),
         to: review.client.email_address, subject: t("mailers.review.version_delivered.subject")
  end

  def revision_requested(review)
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: review.designer_profile.user.email_address,
         subject: t("mailers.review.revision_requested.subject")
  end

  # The designer handed the job back. What the client needs is the reason, the
  # proposal, the difference in price and the deadline to answer.
  def returned_to_client(review)
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: review.client.email_address, subject: t("mailers.review.returned_to_client.subject")
  end

  def proposal_reminder(review)
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: review.client.email_address, subject: t("mailers.review.proposal_reminder.subject")
  end

  def proposal_expired(review)
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: review.client.email_address, subject: t("mailers.review.proposal_expired.subject")
  end

  # The chosen designer has not taken it in twelve hours; the client chooses
  # what happens next.
  def designer_silent(review)
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: review.client.email_address, subject: t("mailers.review.designer_silent.subject")
  end

  def auto_accepted(review)
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: review.client.email_address, subject: t("mailers.review.auto_accepted.subject")
  end

  def paid(review)
    review = @review = reload(review)
    mail to: review.designer_profile.user.email_address,
         subject: t("mailers.review.paid.subject")
  end

  # Nobody took it (decided on 09/10/2026): called off and, when it was paid
  # here, refunded in full.
  def unclaimed(review)
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: @review.client.email_address, subject: t("mailers.review.unclaimed.subject")
  end

  def refunded(review, amount_cents)
    review = @review = reload(review)
    @amount_cents = amount_cents
    mail to: review.client.email_address, subject: t("mailers.review.refunded.subject")
  end

  # An administrator closed a dispute. Both sides are told, together, with the
  # same account of what was decided.
  def settled_by_admin(review, amount_cents)
    review = @review = reload(review)
    @amount_cents = amount_cents
    recipients = [ review.client.email_address, review.designer_profile&.user&.email_address ].compact

    mail to: recipients, subject: t("mailers.review.settled_by_admin.subject")
  end

  # --- Disputes (decided on 08/10/2026) -------------------------------------

  # The client says the delivery is not right. The designer is told, and the
  # administration in copy: if the two do not settle it, someone has to.
  def dispute_opened(review)
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: @review.designer_profile.user.email_address,
         bcc: User.admin.active.pluck(:email_address),
         subject: t("mailers.review.dispute_opened.subject")
  end

  def fix_offered(review)
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: @review.client.email_address, subject: t("mailers.review.fix_offered.subject")
  end

  def fix_accepted(review)
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: @review.designer_profile.user.email_address, subject: t("mailers.review.fix_accepted.subject")
  end

  def dispute_withdrawn(review)
    review = @review = reload(review)
    mail cc: shop_copy(review),
         to: @review.designer_profile.user.email_address, subject: t("mailers.review.dispute_withdrawn.subject")
  end

  # Before the week runs out: silence is about to count as a yes.
  def acceptance_reminder(review, days_left)
    review = @review = reload(review)
    @days_left = days_left
    mail cc: shop_copy(review),
         to: @review.client.email_address,
         subject: t("mailers.review.acceptance_reminder.subject", count: days_left)
  end

  private
    # Reloaded with everything an email reads: a mailer job gets a bare record,
    # and development refuses to walk to an association nobody preloaded.
    def reload(review)
      Review.includes(:client, :design, :review_level, :proposed_level, designer_profile: :user).find(review.id)
    end

    # Decided on 09/10/2026: the workshop the design was made for is copied on
    # every email the site sends about the work — the client's request, the
    # deliveries, the questions, a dispute, a custom job's introduction — so
    # it knows what will reach its press. Not on money: what the designer is
    # paid or the client refunded is between them and the platform. Nil, and
    # so no copy, for a design made for no workshop.
    def shop_copy(review)
      Printer.where(id: Design.where(id: review.design_id).select(:printer_id)).pick(:orders_email)
    end

    def addresses_for(review)
      if review.chosen? && review.designer_profile
        [ review.designer_profile.user.email_address ]
      else
        DesignerProfile.listed.accepting.offering(review.review_level)
                       .includes(:user).map { |profile| profile.user.email_address }
      end
    end
end
