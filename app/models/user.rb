class User < ApplicationRecord
  # One account, exactly one role. See docs/SPEC.md, "Rôles et parcours".
  # Integer values are explicit so reordering the list can never reassign roles.
  enum :role, { client: 0, printer: 1, designer: 2, admin: 3 }, validate: true

  # Roles a visitor may pick when signing up. An administrator is only ever
  # created from the console or by another administrator.
  SELF_ASSIGNABLE_ROLES = %w[ client printer designer ].freeze

  # `has_secure_password` enforces bcrypt's own ceiling (72 bytes) but sets no
  # floor: without one, a one-character password is accepted. `allow_nil`
  # leaves updating an account with no new password untouched.
  MINIMUM_PASSWORD_LENGTH = 8

  has_secure_password
  validates :password, length: { minimum: MINIMUM_PASSWORD_LENGTH }, allow_nil: true
  has_many :sessions, dependent: :destroy

  # Never stored. It exists so the account screen can ask for the current
  # password before changing it, and so the failure has somewhere to hang.
  attr_accessor :current_password

  # Only a printer account has one, and it has exactly one.
  has_one :printer, dependent: :destroy
  # Same for a designer.
  has_one :designer_profile, dependent: :destroy

  # A client's workshop: the shop whose link brought them in, or that accepted
  # their request. Nil until then — the account signs in but creates nothing.
  # See docs/SPEC.md, "Rattachement d'un client à un atelier".
  belongs_to :workshop, class_name: "Printer", optional: true, inverse_of: :clients
  has_many :client_affiliations, foreign_key: :client_id, dependent: :delete_all,
           inverse_of: :client

  has_many :designs, dependent: :destroy
  # A client's own orders. Never destroyed with the account: the workshop has a
  # job in hand, and `client_id` is NOT NULL. Closing an account anonymises
  # these rather than deleting them — that is step 10's business.
  has_many :print_requests, foreign_key: :client_id,
           dependent: :restrict_with_error, inverse_of: :client
  has_many :reviews, foreign_key: :client_id,
           dependent: :restrict_with_error, inverse_of: :client

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :phone, with: ->(p) { p.gsub(/[^\d+]/, "") }

  validates :email_address,
            presence: true,
            uniqueness: { case_sensitive: false },
            format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :first_name, :last_name, presence: true
  validates :terms_accepted_at, presence: true

  scope :active, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }

  def active? = deleted_at.nil?

  def full_name = [ first_name, last_name ].compact_blank.join(" ")

  # A client may create only while a workshop has them — for
  # `clients.attachment_days` from their admission (decided on 09/10/2026),
  # after which they scan the shop's link or QR code again, or ask again.
  def self.attachment_period = Rails.application.config.tshirt.clients.fetch(:attachment_days).days

  # Decided on 09/10/2026: while a review the client ordered on a design made
  # for that shop is open, the thirty days stand still — the client is not
  # left without a shop while a designer works for them.
  REVIEWING_SQL = <<~SQL.squish.freeze
    EXISTS (SELECT 1 FROM reviews INNER JOIN designs ON designs.id = reviews.design_id
            WHERE reviews.client_id = users.id AND designs.printer_id = users.workshop_id
              AND reviews.status IN ('queued', 'in_progress', 'delivered', 'returned_to_client', 'disputed'))
  SQL

  scope :attached_to, ->(printer) {
    where(workshop_id: printer).where("users.workshop_until > ? OR #{REVIEWING_SQL}", Time.current)
  }

  def attached_to_workshop?
    return false if workshop_id.blank?

    workshop_until&.future? || reviewing_for_workshop?
  end

  # The period has run out, but a review holds it open.
  def workshop_period_suspended? = workshop_id.present? && !workshop_until&.future? && reviewing_for_workshop?

  def reviewing_for_workshop?
    return @reviewing_for_workshop if defined?(@reviewing_for_workshop)

    @reviewing_for_workshop = User.where(id: id).where(REVIEWING_SQL).exists?
  end

  # The shop this client creates for today; nil once the period has run out.
  def active_workshop_id = (workshop_id if attached_to_workshop?)

  # Admitted, or admitted again: the period starts over from now. Takes the
  # shop or its id — the id is all it needs, and a record reached through an
  # association nobody preloaded would raise under strict loading.
  def attach_to!(printer)
    update!(workshop_id: printer.is_a?(Printer) ? printer.id : printer,
            workshop_until: User.attachment_period.from_now)
  end

  # Thirty more days, given by the shop — never by the client: when it
  # confirms one of their print requests, or with « Prolonger ». Only for the
  # shop the client belongs to, even if their period has just run out.
  def self.extend_attachment!(client_id:, printer_id:)
    client.where(id: client_id, workshop_id: printer_id)
          .update_all(workshop_until: attachment_period.from_now, updated_at: Time.current)
  end

  # Gives back the time a review held the period still, once the review ends
  # without a delivery (called off, refunded, proposal declined). A delivery
  # gives thirty fresh days instead.
  def self.resume_attachment!(client_id:, printer_id:, paused_seconds:)
    return if paused_seconds.to_i <= 0

    client.where(id: client_id, workshop_id: printer_id).where.not(workshop_until: nil)
          .update_all([ "workshop_until = workshop_until + (? * interval '1 second'), updated_at = ?",
                        paused_seconds.to_i, Time.current ])
  end

  def detach_from_workshop!
    update!(workshop_id: nil, workshop_until: nil)
  end

  # Marks the account as gone without destroying it: invoices and print requests
  # still reference it until the purge task runs.
  def soft_delete!
    transaction do
      Session.where(user_id: id).destroy_all
      update!(deleted_at: Time.current)
    end
  end

  # A deleted account must never authenticate again, even with valid credentials.
  def self.authenticate_by(attributes)
    super&.then { |user| user if user.active? }
  end
end
