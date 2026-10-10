# A client joining a workshop: admitted at once by the workshop's own code, or
# asked for from the directory and decided by the workshop. See docs/SPEC.md,
# "Rattachement d'un client à un atelier".
#
# The client's current workshop is `users.workshop_id`, valid until
# `users.workshop_until`; these rows are how it got there, and the queue of
# what is still waiting.
class ClientAffiliation < ApplicationRecord
  enum :status, { pending: 0, accepted: 1, declined: 2, cancelled: 3 }, validate: true
  # `invitation`: the code on the poster, the QR code or a named link — admits
  #   only a client who has never been this shop's.
  # `request`: the directory, a link without its code, or a former client.
  # `sheet`: a numbered single-use sheet, from 09/10 to 10/10/2026. The
  #   sheets are gone; the value stays for the rows they admitted.
  #
  # `channel` says which of the shop's supports it was: the values of
  # `workshop_link_visits.source` — `qr`, `link`, `email`, or the key of one of
  # the shop's named links. Empty for the directory.
  enum :source, { invitation: 0, request: 1, sheet: 2 }, prefix: :from, validate: true

  belongs_to :client, class_name: "User"
  belongs_to :printer

  validates :channel, length: { maximum: 40 }
  validate :client_is_a_client

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # The poster admits once (decided on 09/10/2026): a client who has been this
  # shop's before — whose thirty days have run out — asks again, so that
  # scanning the counter again cannot keep the AI running without the shop.
  def self.first_time?(client:, printer:)
    client.nil? || !accepted.exists?(client: client, printer: printer)
  end

  # In at once, by the shop's code, leaving any other shop. Already this
  # shop's client: nothing to do — only the shop extends a client's period.
  def self.admit!(client:, printer:, channel: nil)
    return true if client.active_workshop_id == printer.id

    transaction do
      where(client: client, status: :pending).update_all(status: statuses[:cancelled], decided_at: Time.current, updated_at: Time.current)
      create!(client: client, printer: printer, source: :invitation, channel: channel,
              status: :accepted, decided_at: Time.current)
      client.attach_to!(printer)
      true
    end
  end

  # A request to the workshop. Asking another shop replaces the one still open:
  # a client waits on one answer at a time. Nil when there is nothing to ask —
  # already that shop's client, or already waiting on it. A client whose period
  # with a shop has run out asks it again like anyone else.
  # `channel` is set when a former client came back by one of the shop's
  # supports: the shop sees where the request came from.
  def self.request!(client:, printer:, channel: nil)
    return nil if client.active_workshop_id == printer.id

    transaction do
      open = find_by(client: client, status: :pending)
      return nil if open&.printer_id == printer.id

      open&.update!(status: :cancelled, decided_at: Time.current)
      create!(client: client, printer: printer, source: :request, channel: channel)
    end
  end

  def accept!
    transaction do
      update!(status: :accepted, decided_at: Time.current)
      client.attach_to!(printer_id)
    end
  end

  def decline! = update!(status: :declined, decided_at: Time.current)

  # For each of `client_ids`, the row that last brought them to `printer`:
  # the shop's list says how each client came.
  def self.latest_admissions(printer_id:, client_ids:)
    accepted.where(printer_id: printer_id, client_id: client_ids)
            .order(:decided_at, :id).to_a.index_by(&:client_id)
  end

  private
    def client_is_a_client
      errors.add(:client, :invalid) unless client&.client?
    end
end
