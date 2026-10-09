class SubscriptionMailer < ApplicationMailer
  # A card that stopped working. The listing does not vanish the same day, so
  # the useful thing to say is exactly when it will, and where to fix it.
  def payment_failed(subscription)
    @subscription = Subscription.includes(printer: :user).find(subscription.id)
    @printer = @subscription.printer
    @hidden_from = subscription.hidden_from

    mail to: @printer.user.email_address,
         subject: t("mailers.subscription.payment_failed.subject")
  end

  # The workshop's clients have used the month's generations of its plan. Said
  # once a month, with the way out: Atelier+ has no ceiling.
  def generation_quota_reached(printer)
    # Reloaded with what the email reads: a mailer job gets a bare record.
    @printer = Printer.includes(:user, :subscription).find(printer.id)
    @limit = PrinterGenerationQuota.for(@printer).limit
    @reset_on = Time.zone.today.next_month.beginning_of_month

    mail to: @printer.user.email_address,
         subject: t("mailers.subscription.generation_quota_reached.subject", count: @limit)
  end
end
