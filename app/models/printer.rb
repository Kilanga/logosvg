class Printer < ApplicationRecord
  # draft → pending_review → published, and suspended by an administrator.
  # Not a state machine in the AASM sense: the spec reserves those for Design,
  # PrintRequest and Review. Transitions here are a handful of admin decisions.
  enum :status, { draft: 0, pending_review: 1, published: 2, suspended: 3 }, validate: true
  enum :textile_label, { none: 0, gots: 1, oeko_tex: 2 }, prefix: :label, validate: true

  PLACEMENTS = %w[ chest_center chest_left back_full back_top sleeve tote_bag ].freeze
  SHIPPING_ZONES = %w[ france europe worldwide ].freeze
  POSTAL_CODE = /\A\d{5}\z/
  HEX_COLOUR = /\A#\h{6}\z/

  belongs_to :user
  # Primary first, then alphabetical: the public page leads with the technique
  # the shop would pick for a client who does not know.
  has_many :techniques, -> { primary_first },
           class_name: "PrinterTechnique", dependent: :destroy, inverse_of: :printer
  accepts_nested_attributes_for :techniques, allow_destroy: true, reject_if: :all_blank

  # The orders the shop has received. Restricted rather than cascaded: a
  # listing is not deleted out from under a job in progress.
  has_many :print_requests, dependent: :restrict_with_error, inverse_of: :printer

  has_one :subscription, dependent: :destroy
  has_many :link_visits, class_name: "WorkshopLinkVisit", dependent: :delete_all,
           inverse_of: :printer

  has_one_attached :logo
  has_many_attached :photos

  before_validation :assign_slug, on: :create

  # Geocoded on every address change, from a background job: the form must not
  # wait on a third party, and a shop that moves must not keep its old pin.
  # Not named `address_changed?`: that is Active Record's own dirty-tracking
  # method for the address column, and overriding it breaks change detection.
  after_commit :geocode_later, on: %i[ create update ], if: :address_fields_changed?

  normalizes :orders_email, with: ->(e) { e.strip.downcase }
  normalizes :website, with: ->(w) { w.strip.presence }

  validates :name, presence: true, length: { maximum: 120 }
  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9-]+\z/ }
  validates :orders_email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :postal_code, format: { with: POSTAL_CODE }, allow_blank: true
  validates :brand_color, format: { with: HEX_COLOUR }, allow_blank: true
  validates :max_print_width_cm, :max_print_height_cm, :min_order_qty,
            numericality: { greater_than: 0 }, allow_nil: true
  validates :placements, inclusion: { in: PLACEMENTS }, allow_blank: true
  validates :shipping_zones, inclusion: { in: SHIPPING_ZONES }, allow_blank: true

  # Everything a visitor needs before the shop can be shown at all.
  validates :address, :postal_code, :city, :description, presence: true, if: :leaving_draft?

  # A listing with no technique cannot be matched to any design: it would appear
  # in the directory and be compatible with nothing.
  validate :declares_at_least_one_technique, if: :leaving_draft?

  # The technique kept when a client answers "I don't know". Validated here
  # rather than in the form: the rule belongs to the shop as a whole, and the
  # database enforces it too.
  validate :exactly_one_primary_technique

  # A listing is public once it is published *and* paid for. This scope is the
  # only place that answers it: the directory, the map, the shop page, the
  # workshop link and every compatibility check all go through here, so a shop
  # whose subscription lapses disappears from all of them at once.
  scope :listed, -> { published.where(id: Subscription.visible_printer_ids) }
  scope :located, -> { where.not(latitude: nil, longitude: nil) }
  scope :shipping_nationwide, -> { where(ships: true) }
  scope :by_prominence, -> { order(featured: :desc, name: :asc) }
  scope :in_department, ->(code) { where("left(postal_code, 2) = ?", code.to_s[0, 2]) }
  # ILIKE, not unaccent: the extension is not installed, and a directory of
  # French towns matches well enough on case alone.
  scope :matching, ->(term) {
    pattern = "%#{sanitize_sql_like(term.to_s.strip)}%"
    where("name ILIKE :q OR city ILIKE :q", q: pattern)
  }

  # Great-circle distance, in kilometres, against the Earth's mean radius. A
  # bounding box narrows the rows cheaply first — roughly 111 km to a degree of
  # latitude — then the exact formula decides, so a radius is a circle and not a
  # square. LEAST(1, …) guards acos against the rounding that makes a point
  # compared with itself come out just above 1.
  #
  # Written out rather than interpolated: a `where` built by string
  # interpolation is indistinguishable, to a scanner and to a reader, from one
  # that splices in user input.
  DISTANCE_KM_SQL = <<~SQL.squish.freeze
    6371 * acos(LEAST(1,
      cos(radians(:latitude)) * cos(radians(printers.latitude)) *
      cos(radians(printers.longitude) - radians(:longitude)) +
      sin(radians(:latitude)) * sin(radians(printers.latitude))
    )) <= :radius
  SQL

  KM_PER_DEGREE = 111.0

  scope :within_km, ->(latitude:, longitude:, radius:) {
    delta_lat = radius / KM_PER_DEGREE
    delta_lng = radius / (KM_PER_DEGREE * Math.cos(latitude * Math::PI / 180)).abs

    located
      .where(latitude: (latitude - delta_lat)..(latitude + delta_lat))
      .where(longitude: (longitude - delta_lng)..(longitude + delta_lng))
      .where(DISTANCE_KM_SQL, latitude: latitude, longitude: longitude, radius: radius)
  }

  # Public URLs carry the slug, never the sequential id.
  def to_param = slug

  def full_address = [ address, postal_code, city ].compact_blank.join(", ")

  # The brands a shop stocks are a free list, typed as one line. Kept as an
  # array in the database so the directory can filter on it later.
  def textile_brands_list = textile_brands.join(", ")

  def textile_brands_list=(value)
    self.textile_brands = value.to_s.split(",").map(&:strip).compact_blank
  end

  def located? = latitude.present? && longitude.present?

  # The instance side of the `listed` scope. Both have to agree, or a shop
  # disappears from the directory while its own page stays up — which is how a
  # lapsed subscription would keep being reachable by anyone holding the link.
  def listed? = published? && subscription&.visible?.present?

  # What this shop would use for a client who answers "I don't know".
  def primary_technique = live_techniques.find(&:primary?)

  def technique_for(key) = live_techniques.find { |t| t.technique == key.to_s }

  def practises?(key) = technique_for(key).present?

  def technique_keys = live_techniques.map(&:technique)

  private
    def leaving_draft? = !draft?

    # The rows that will still exist once the form is saved: a technique the
    # printer just unchecked must not keep the listing alive, nor hold the
    # primary flag.
    def live_techniques = techniques.reject(&:marked_for_destruction?)

    def declares_at_least_one_technique
      errors.add(:techniques, :blank) if live_techniques.empty?
    end

    def exactly_one_primary_technique
      return if live_techniques.empty?

      case live_techniques.count(&:primary?)
      when 1 then nil
      when 0 then errors.add(:techniques, :no_primary)
      else errors.add(:techniques, :several_primaries)
      end
    end

    def address_fields_changed?
      saved_change_to_address? || saved_change_to_postal_code? || saved_change_to_city?
    end

    def geocode_later = GeocodePrinterJob.perform_later(self)

    # A readable, stable slug. Collisions get a numbered suffix rather than a
    # random one, so the URL still says what it is.
    def assign_slug
      return if slug.present? || name.blank?

      base = name.parameterize
      candidate = base
      suffix = 2

      while self.class.where(slug: candidate).exists?
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end

      self.slug = candidate
    end
end
