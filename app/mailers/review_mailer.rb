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

  # An administrator closed a dispute. Both sides are told the same account of
  # what was decided — each in an email of their own, since 15/10/2026: put
  # together in « À », each read the other's address.
  def settled_by_admin(review, amount_cents, recipient: "client")
    review = @review = reload(review)
    @amount_cents = amount_cents
    @for_designer = recipient == "designer"
    to = @for_designer ? review.designer_profile&.user&.email_address : review.client.email_address
    return message.perform_deliveries = false if to.blank?

    mail to: to, subject: t("mailers.review.settled_by_admin.subject")
  end

  # The client refused the designer's proposal, or let it lapse: the review is
  # closed, and the designer is told (reported on 15/10/2026: they were not),
  # with the share that stays theirs when they had started.
  def proposal_declined(review)
    review = @review = reload(review)
    return message.perform_deliveries = false if review.designer_profile.nil?

    mail to: review.designer_profile.user.email_address, subject: t("mailers.review.proposal_declined.subject")
  end

  # A message in the conversation, to the side that did not write it (G3,
  # decided on 15/10/2026). One per unread run: see ReviewMessage.
  def new_message(review_message)
    @message = ReviewMessage.includes(:author).find(review_message.id)
    review = @review = reload(@message.review_id)
    @to_designer = @message.author_id == review.client_id
    to = @to_designer ? review.designer_profile&.user&.email_address : review.client.email_address
    return message.perform_deliveries = false if to.blank?

    mail to: to, subject: t("mailers.review.new_message.subject", name: @message.author.first_name)
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
      Review.includes(:client, :design, :review_level, :proposed_level, designer_profile: :user)
            .find(review.is_a?(Review) ? review.id : review)
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

    # Every designer who takes the level can see the job in their studio; the
    # email is only a nudge, and each address costs one of the 300 Brevo sends
    # of the day (decided on 10/10/2026). So at most `notify_designers_max`,
    # the shop's recommended designer first, the others drawn at random so no
    # one is always left out.
    def addresses_for(review)
      if review.chosen? && review.designer_profile
        [ review.designer_profile.user.email_address ]
      else
        candidates = DesignerProfile.listed.accepting.offering(review.review_level).includes(:user).to_a
        recommended_id = Printer.where(id: Design.where(id: review.design_id).select(:printer_id))
                                .pick(:recommended_designer_profile_id)
        first, others = candidates.partition { |profile| profile.id == recommended_id }

        (first + others.shuffle).first(notify_designers_max).map { |profile| profile.user.email_address }
      end
    end

    def notify_designers_max = Rails.application.config.tshirt.reviews.fetch(:notify_designers_max)
end
