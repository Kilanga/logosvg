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

  # A client may create only once a workshop has them.
  def attached_to_workshop? = workshop_id.present?

  # Marks the account as gone without destroying it: invoices and print requests
  # still reference it until the purge task runs.
  def soft_delete!
    transaction do
      sessions.destroy_all
      update!(deleted_at: Time.current)
    end
  end

  # A deleted account must never authenticate again, even with valid credentials.
  def self.authenticate_by(attributes)
    super&.then { |user| user if user.active? }
  end
end
