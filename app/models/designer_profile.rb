class DesignerProfile < ApplicationRecord
  # pending_review → active, and suspended by an administrator. Not an AASM
  # machine: the spec reserves those for Design, PrintRequest and Review, and
  # these are a handful of admin decisions.
  STATUSES = %w[ pending_review active suspended ].freeze

  SPECIALTIES = %w[ illustration lettering logo mascotte vectorisation retouche ].freeze
  LANGUAGES = %w[ fr en es de it ].freeze

  belongs_to :user

  has_many :designer_levels, dependent: :destroy
  has_many :review_levels, through: :designer_levels
  # Work already in hand is never destroyed with a profile: it has been paid
  # for, and an administrator settles what is left.
  has_many :reviews, dependent: :restrict_with_error, inverse_of: :designer_profile

  has_one_attached :avatar
  has_many_attached :portfolio

  geocoded_by :geocoding_address
  after_commit :geocode_later, on: %i[ create update ], if: :address_changed_for_geocoding?

  normalizes :display_name, with: ->(n) { n.strip }

  validates :display_name, presence: true, length: { maximum: 80 }
  validates :status, inclusion: { in: STATUSES }
  validates :specialties, inclusion: { in: SPECIALTIES }, allow_blank: true
  validates :languages, inclusion: { in: LANGUAGES }, allow_blank: true
  validates :ratings_count, numericality: { greater_than_or_equal_to: 0 }

  # Enough to be judged, checked when an administrator activates the profile
  # rather than on every save: a designer writing their page over three
  # sittings must be able to save it half-finished.
  validates :bio, presence: true, length: { minimum: 40 }, on: :activation
  validates :city, presence: true, on: :activation
  validate :declares_at_least_one_level, on: :activation

  STATUSES.each { |value| define_method("#{value}?") { status == value } }

  scope :listed, -> { where(status: "active") }
  scope :located, -> { where.not(latitude: nil, longitude: nil) }
  scope :by_reputation, -> { order(Arel.sql("rating_avg DESC NULLS LAST, ratings_count DESC, display_name ASC")) }
  scope :accepting, -> { where(accepting_work: true, payouts_enabled: true) }
  scope :offering, ->(level) { joins(:designer_levels).where(designer_levels: { review_level: level }) }

  # The rule the whole step exists for: nothing is ever assigned to a designer
  # who has not been vetted, cannot be paid, or has stepped away.
  #
  # See docs/SPEC.md — "Un graphiste sans versements activés ne peut rien
  # prendre".
  def can_take_work? = active? && payouts_enabled? && accepting_work?

  # Why not, in the designer's own terms. Returns nil when they can.
  def unavailable_reason
    return nil if can_take_work?
    return :suspended if suspended?
    return :pending_review if pending_review?
    return :payouts_disabled unless payouts_enabled?

    :not_accepting
  end

  def accepts?(review_level) = review_level_ids.include?(review_level.id)

  # Whether an administrator could activate this profile as it stands.
  def ready_for_activation? = valid?(:activation)

  # How often this designer hands work back rather than doing it, over the last
  # thirty days. A few returns are healthy — it is what the mechanism is for;
  # a majority means either the levels are wrong or the designer is picking.
  #
  # Counted over reviews they actually took, so a quiet month does not read as
  # a perfect one.
  def return_rate(days: 30)
    self.class.return_rates([ self ], days: days)[id]
  end

  # The same figure for many designers, in two queries rather than two each.
  # `includes(:reviews)` does not help here: a `where` on a loaded association
  # goes back to the database anyway, which is what made the administration's
  # dashboard cost two queries per profile.
  def self.return_rates(profiles, days: 30)
    scope = Review.where(designer_profile: profiles, created_at: days.days.ago..)
    totals = scope.group(:designer_profile_id).count
    returned = scope.where.not(returned_at: nil).group(:designer_profile_id).count

    totals.to_h { |id, total| [ id, (returned.fetch(id, 0).to_f / total).round(3) ] }
  end

  def return_rate_alarming?(days: 30)
    rate = return_rate(days: days)
    return false if rate.nil?

    rate >= Rails.application.config.tshirt.reviews[:return_rate_alert_threshold]
  end

  def onboarding_started? = onboarding_started_at.present?

  def rated? = ratings_count.positive?

  def to_param = id.to_s

  private
    def geocoding_address = [ city, "France" ].compact_blank.join(", ")

    def address_changed_for_geocoding? = saved_change_to_city?

    def geocode_later = GeocodeDesignerProfileJob.perform_later(self)

    def declares_at_least_one_level
      errors.add(:review_levels, :blank) if designer_levels.reject(&:marked_for_destruction?).empty?
    end
end
