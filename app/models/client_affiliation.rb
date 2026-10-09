# A client joining a workshop: admitted at once by the workshop's own code, or
# asked for from the directory and decided by the workshop. See docs/SPEC.md,
# "Rattachement d'un client à un atelier".
#
# The client's current workshop is `users.workshop_id`; these rows are how it
# got there, and the queue of what is still waiting.
class ClientAffiliation < ApplicationRecord
  enum :status, { pending: 0, accepted: 1, declined: 2, cancelled: 3 }, validate: true
  # `invitation`: the code on the poster, the QR code or a named link.
  # `request`: the directory, or a link without its code.
  enum :source, { invitation: 0, request: 1 }, prefix: :from, validate: true

  belongs_to :client, class_name: "User"
  belongs_to :printer

  validate :client_is_a_client

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # The workshop's code: the client is in at once, and leaves any other shop.
  def self.admit!(client:, printer:)
    transaction do
      where(client: client, status: :pending).update_all(status: statuses[:cancelled], decided_at: Time.current, updated_at: Time.current)
      create!(client: client, printer: printer, source: :invitation, status: :accepted, decided_at: Time.current)
      client.update!(workshop_id: printer.id)
    end
  end

  # A request to the workshop. Asking another shop replaces the one still open:
  # a client waits on one answer at a time. Nil when there is nothing to ask —
  # already that shop's client, or already waiting on it.
  def self.request!(client:, printer:)
    return nil if client.workshop_id == printer.id

    transaction do
      open = find_by(client: client, status: :pending)
      return nil if open&.printer_id == printer.id

      open&.update!(status: :cancelled, decided_at: Time.current)
      create!(client: client, printer: printer, source: :request)
    end
  end

  def accept!
    transaction do
      update!(status: :accepted, decided_at: Time.current)
      client.update!(workshop_id: printer_id)
    end
  end

  def decline! = update!(status: :declined, decided_at: Time.current)

  private
    def client_is_a_client
      errors.add(:client, :invalid) unless client&.client?
    end
end
