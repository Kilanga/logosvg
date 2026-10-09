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
  # `sheet`: a numbered single-use sheet (WorkshopInvite), the shop's
  #   agreement given to one person.
  enum :source, { invitation: 0, request: 1, sheet: 2 }, prefix: :from, validate: true

  belongs_to :client, class_name: "User"
  belongs_to :printer

  validate :client_is_a_client

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  # The poster admits once (decided on 09/10/2026): a client who has been this
  # shop's before — whose thirty days have run out — asks again, so that
  # scanning the counter again cannot keep the AI running without the shop.
  def self.first_time?(client:, printer:)
    client.nil? || !accepted.exists?(client: client, printer: printer)
  end

  # In at once, by the shop's code or one of its sheets, leaving any other
  # shop. A sheet is spent in the same transaction: if another sign-up spent
  # it first, nothing happens and this returns false. Already this shop's
  # client: nothing to do — only the shop extends a client's period.
  def self.admit!(client:, printer:, source: :invitation, invite: nil)
    return true if client.active_workshop_id == printer.id

    transaction do
      raise ActiveRecord::Rollback if invite && !invite.consume!(client)

      where(client: client, status: :pending).update_all(status: statuses[:cancelled], decided_at: Time.current, updated_at: Time.current)
      create!(client: client, printer: printer, source: source, status: :accepted, decided_at: Time.current)
      client.attach_to!(printer)
      true
    end || false
  end

  # A request to the workshop. Asking another shop replaces the one still open:
  # a client waits on one answer at a time. Nil when there is nothing to ask —
  # already that shop's client, or already waiting on it. A client whose period
  # with a shop has run out asks it again like anyone else.
  def self.request!(client:, printer:)
    return nil if client.active_workshop_id == printer.id

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
      client.attach_to!(printer_id)
    end
  end

  def decline! = update!(status: :declined, decided_at: Time.current)

  private
    def client_is_a_client
      errors.add(:client, :invalid) unless client&.client?
    end
end
