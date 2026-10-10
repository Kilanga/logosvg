# Delivers the emails sent with `deliver_later` (decided on 10/10/2026).
#
# The default job tries once: if Brevo refuses — its 300 a day are spent, the
# relay is busy, the network drops — the email is simply lost, a password
# reset or a print request included. This one tries again every half hour for
# a day, which carries an email over the daily limit to the next morning, and
# counts what it finally gives up on for the administration's dashboard.
class MailDeliveryJob < ActionMailer::MailDeliveryJob
  # Brevo says « limit » or « credit » when the day's quota is spent; whether
  # it does so with a 4xx or a 5xx, the email is worth trying again.
  QuotaReached = Class.new(StandardError)
  QUOTA_WORDING = /limit|quota|credit/i

  TRANSIENT = [
    Net::SMTPServerBusy, Net::OpenTimeout, Net::ReadTimeout,
    Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::ETIMEDOUT, QuotaReached
  ].freeze

  retry_on(*TRANSIENT, wait: 30.minutes, attempts: 48) do |_job, error|
    MailDeliveryDay.record_failed!
    Rails.logger.error("[mail] given up after a day: #{error.class}: #{error.message}")
  end

  def perform(...)
    super
  rescue Net::SMTPFatalError => error
    raise QuotaReached, error.message if error.message.match?(QUOTA_WORDING)

    MailDeliveryDay.record_failed!
    raise
  end
end
