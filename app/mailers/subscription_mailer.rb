class SubscriptionMailer < ApplicationMailer
  # A card that stopped working. The listing does not vanish the same day, so
  # the useful thing to say is exactly when it will, and where to fix it.
  def payment_failed(subscription)
    @subscription = subscription
    @printer = subscription.printer
    @hidden_from = subscription.hidden_from

    mail to: @printer.user.email_address,
         subject: t("mailers.subscription.payment_failed.subject")
  end
end
