# The emails of one day: how many recipients the site sent to, and how many
# emails were given up on. Counted, never logged: who was written to is no
# business of this table. See MailDeliveryCounter and MailDeliveryJob.
class MailDeliveryDay < ApplicationRecord
  def self.daily_limit = Rails.application.config.tshirt.emails.fetch(:daily_limit)
  def self.alert_ratio = Rails.application.config.tshirt.emails.fetch(:alert_ratio)

  # Atomic, like the link visits: two jobs finishing in the same second must
  # both be counted.
  def self.record_sent!(recipients)
    return if recipients.to_i <= 0

    upsert(row(recipients_count: recipients.to_i), unique_by: :day,
           on_duplicate: Arel.sql("recipients_count = mail_delivery_days.recipients_count + EXCLUDED.recipients_count, updated_at = EXCLUDED.updated_at"))
  end

  def self.record_failed!
    upsert(row(failed_count: 1), unique_by: :day,
           on_duplicate: Arel.sql("failed_count = mail_delivery_days.failed_count + 1, updated_at = EXCLUDED.updated_at"))
  end

  def self.today = find_by(day: Time.zone.today) || new(day: Time.zone.today)

  def near_limit? = recipients_count >= (self.class.daily_limit * self.class.alert_ratio)

  def self.row(counts) = { day: Time.zone.today, created_at: Time.current, updated_at: Time.current, **counts }
  private_class_method :row
end
