# One email a shop sent to give its link to a client (decided on 10/10/2026).
#
# A service to a client the shop already spoke to, never prospecting: an
# address gets the link once from a given shop, and a shop sends only so many
# a day (`clients.link_emails_per_day`). Both are counted here.
#
# The address is not kept. `recipient_digest` is a keyed hash of it: enough to
# recognise the same address next time, and nothing anyone reading the table
# could turn back into an address — or match against another list.
class WorkshopLinkEmail < ApplicationRecord
  MESSAGE_MAX = 300

  belongs_to :printer, inverse_of: :link_emails

  validates :recipient_digest, presence: true

  def self.digest(address)
    OpenSSL::HMAC.hexdigest("SHA256", key, address.to_s.strip.downcase)
  end

  def self.daily_limit = Rails.application.config.tshirt.clients.fetch(:link_emails_per_day)

  def self.sent_today(printer) = where(printer: printer, created_at: Time.current.all_day).count

  # Derived from the application's secret, under a name of its own: rotating
  # `secret_key_base` forgets which addresses were written to, nothing more.
  def self.key = @key ||= Rails.application.key_generator.generate_key("workshop_link_emails/recipient", 32)
end
