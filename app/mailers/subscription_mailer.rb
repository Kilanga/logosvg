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

  # The workshop has used the month's print requests of its plan. Said once a
  # month, with the way out: Atelier+ has no ceiling. Nothing is blocked —
  # the email says so, lest the workshop think its clients are turned away.
  def request_quota_reached(printer)
    # Reloaded with what the email reads: a mailer job gets a bare record.
    @printer = Printer.includes(:user, :subscription).find(printer.id)
    @limit = PrinterRequestQuota.for(@printer).limit
    @reset_on = Time.zone.today.next_month.beginning_of_month

    mail to: @printer.user.email_address,
         subject: t("mailers.subscription.request_quota_reached.subject", count: @limit)
  end
end
