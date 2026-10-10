# Every email the site sends is counted, per recipient, against the daily
# Brevo limit. See MailDeliveryCounter.
Rails.application.config.after_initialize do
  ActionMailer::Base.register_observer(MailDeliveryCounter)
end
