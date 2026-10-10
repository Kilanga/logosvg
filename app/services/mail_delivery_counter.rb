# Counts every email the site sends, per recipient — the way Brevo counts
# against its 300 a day (decided on 10/10/2026). Registered as an Action
# Mailer observer: it runs once a message has actually been handed over.
class MailDeliveryCounter
  def self.delivered_email(message)
    recipients = [ message.to, message.cc, message.bcc ].flatten.compact.map(&:downcase).uniq
    MailDeliveryDay.record_sent!(recipients.size)
  end
end
