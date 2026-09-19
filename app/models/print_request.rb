class PrintRequest < ApplicationRecord
  include AASM

  TEXTILE_SOURCES = %w[ printer client ].freeze

  belongs_to :design
  belongs_to :client, class_name: "User"
  belongs_to :printer

  # Copies, taken at send time. The design may father variants and the workshop
  # must keep printing what was actually ordered — see docs/SPEC.md, "Copie des
  # fichiers à l'envoi".
  has_one_attached :final_file
  has_one_attached :preview_png

  has_secure_token :token
  has_secure_token :confirmation_token

  normalizes :contact_email, with: ->(e) { e.strip.downcase }

  validates :textile_source, inclusion: { in: TEXTILE_SOURCES }
  validates :placements, inclusion: { in: Printer::PLACEMENTS }, allow_blank: true
  validates :print_width_cm, numericality: { in: 3..60 }
  validates :contact_name, :contact_email, presence: true
  validates :contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :consent_text_version, :consented_at, presence: true

  # A workshop cannot quote a job with no garments in it, and the sizes are the
  # only place the quantity comes from.
  validate :orders_at_least_one_garment
  validate :sizes_are_known_and_countable

  # Both of these judge the request *as it was sent*, so they only run then. A
  # shop that raises its minimum next month, or a desired date that simply
  # arrives, must not turn a request already in the workshop's hands into a
  # record that can no longer be saved — which would leave it stuck in its
  # state for ever.
  validate :quantity_reaches_the_shop_minimum, on: :create
  validate :desired_on_is_not_in_the_past, on: :create

  before_validation :count_garments

  scope :newest_first, -> { order(sent_at: :desc, created_at: :desc) }
  scope :awaiting_acknowledgement, -> { where(status: "sent") }

  # `sent` is the initial state: a print request exists because it was sent.
  # There is no draft — the form is the draft.
  aasm column: :status, whiny_transitions: true do
    state :sent, initial: true
    state :acknowledged
    state :quoted
    state :in_production
    state :completed
    state :canceled
    state :expired

    event :acknowledge do
      transitions from: :sent, to: :acknowledged
      after { self.acknowledged_at = Time.current }
    end

    event :quote do
      transitions from: :acknowledged, to: :quoted
      after { self.quoted_at = Time.current }
    end

    event :start_production do
      transitions from: :quoted, to: :in_production
    end

    event :complete do
      transitions from: :in_production, to: :completed
    end

    # The client's own way out, and only while the shop has not begun.
    event :cancel do
      transitions from: [ :sent, :acknowledged ], to: :canceled
    end

    # Swept by a job. Only a request the shop never acknowledged can expire.
    event :expire do
      transitions from: :sent, to: :expired
    end
  end

  # Public URLs carry the token, never the sequential id.
  def to_param = token

  # The one step the workshop can take from where the job stands, or nil when
  # there is none. Asked here rather than worked out in a view, and written out
  # rather than sent: no method name is ever built from a string.
  #
  # `cancel` is not among them — calling a job off is the client's to do.
  def next_workshop_event
    return :acknowledge if may_acknowledge?
    return :quote if may_quote?
    return :start_production if may_start_production?
    return :complete if may_complete?

    nil
  end

  def open? = %w[ sent acknowledged quoted in_production ].include?(status)

  def awaiting_acknowledgement? = sent?

  # A confirmation link is dead once the request has moved on or been called
  # off — an antivirus following an old link must not revive anything.
  def confirmable? = sent? && !confirmation_expired?

  def confirmation_expired?
    return false if sent_at.nil?

    sent_at < settings[:confirmation_token_valid_days].days.ago
  end

  def reminder_due?
    sent? && reminded_at.nil? && sent_at.present? &&
      sent_at <= settings[:reminder_after_hours].hours.ago
  end

  def expiry_due?
    sent? && sent_at.present? && sent_at <= settings[:expire_after_days].days.ago
  end

  # Sizes in the order the settings list them, not the order they were typed.
  def ordered_sizes
    self.class.garment_sizes.filter_map do |size|
      quantity = sizes[size].to_i
      [ size, quantity ] if quantity.positive?
    end
  end

  def self.garment_sizes = Rails.application.config.tshirt.print_requests[:garment_sizes]

  def printer_supplies_textile? = textile_source == "printer"

  private
    def settings = Rails.application.config.tshirt.print_requests

    def count_garments
      self.total_qty = sizes.values.sum { |quantity| quantity.to_i.clamp(0, max_per_size) }
    end

    def max_per_size = settings[:max_qty_per_size]

    def orders_at_least_one_garment
      errors.add(:sizes, :blank) unless total_qty.to_i.positive?
    end

    # A size the shop has never heard of would reach the email as a line nobody
    # can price.
    def sizes_are_known_and_countable
      unknown = sizes.keys - self.class.garment_sizes
      errors.add(:sizes, :unknown_size, sizes: unknown.join(", ")) if unknown.any?

      return if sizes.values.all? { |quantity| quantity.to_s.match?(/\A\d*\z/) }

      errors.add(:sizes, :not_a_number)
    end

    def quantity_reaches_the_shop_minimum
      minimum = printer&.min_order_qty
      return if minimum.blank? || total_qty.to_i >= minimum

      errors.add(:sizes, :below_minimum, count: minimum)
    end

    def desired_on_is_not_in_the_past
      errors.add(:desired_on, :in_the_past) if desired_on.present? && desired_on < Date.current
    end
end
