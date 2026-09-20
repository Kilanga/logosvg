# What a client buys when they ask for a designer's check.
#
# The rows are data, not code: an administrator edits them at step 9. The keys
# are named here only because the application reasons about them — a custom
# level is quoted rather than priced, and that is a rule, not a label.
class ReviewLevel < ApplicationRecord
  KEYS = %w[ check retouch custom ].freeze

  has_many :designer_levels, dependent: :destroy
  has_many :designer_profiles, through: :designer_levels

  validates :key, presence: true, inclusion: { in: KEYS }, uniqueness: true
  validates :name, presence: true
  validates :turnaround_hours, numericality: { greater_than: 0 }
  validates :revisions_included, numericality: { greater_than_or_equal_to: 0 }
  validates :price_cents, numericality: { greater_than: 0 }, allow_nil: true

  # A level with no price is quoted by the designer, case by case.
  validates :price_cents, presence: true, unless: :quoted?

  scope :offered, -> { where(active: true).order(:position) }

  def quoted? = key == "custom"

  def price_euros = price_cents ? price_cents / 100.0 : nil

  # The platform's share, in cents, rounded down so the designer never loses a
  # centime to rounding. The rate is a configured value — see settings.yml.
  def platform_fee_cents(amount_cents = price_cents)
    return 0 if amount_cents.nil?

    (amount_cents * Rails.application.config.tshirt.reviews[:platform_fee_rate]).floor
  end

  def designer_share_cents(amount_cents = price_cents)
    return 0 if amount_cents.nil?

    amount_cents - platform_fee_cents(amount_cents)
  end
end
