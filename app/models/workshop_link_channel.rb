# A named way of sharing a shop's link: "flyer", "salon de Rennes", "Instagram".
#
# Each one is the shop's link with `?s=<key>` on the end, so the statistics can
# say which paper or which post actually brought people in. The key is what gets
# printed, so it never changes: renaming a channel changes what the shop reads,
# not what a flyer already in circulation points to.
class WorkshopLinkChannel < ApplicationRecord
  # A shop juggles a handful of channels, not hundreds. The cap is also what
  # keeps the statistics legible.
  LIMIT = 10

  # `link` is the plain address, `qr` the poster and `email` the link a shop
  # emails to a client: those are always there.
  RESERVED = WorkshopLinkVisit::BUILT_IN

  belongs_to :printer, inverse_of: :link_channels

  before_validation :assign_key, on: :create

  normalizes :label, with: ->(label) { label.squish }

  validates :label, presence: true, length: { maximum: 40 }
  validate :label_makes_a_key, on: :create
  validate :within_limit, on: :create

  private
    # Same idea as a shop's slug: readable, and a collision gets a number rather
    # than a random suffix, so the URL still says what it is. Uniqueness itself
    # is the index's job.
    def assign_key
      return if key.present? || label.blank?

      base = label.parameterize.first(30).delete_suffix("-")
      return if base.blank?

      candidate = base
      suffix = 2

      while RESERVED.include?(candidate) || printer.link_channels.exists?(key: candidate)
        candidate = "#{base}-#{suffix}"
        suffix += 1
      end

      self.key = candidate
    end

    # A label of nothing but punctuation has no key to travel in a URL.
    def label_makes_a_key
      errors.add(:label, :invalid) if label.present? && key.blank?
    end

    def within_limit
      return if printer.nil? || printer.link_channels.count < LIMIT

      errors.add(:base, :limit_reached, count: LIMIT)
    end
end
