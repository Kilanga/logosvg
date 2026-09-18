# What one shop does with one technique.
#
# The technique key is the *mode* — what a client chooses, and what the
# generation service is asked for. Everything else here belongs to the shop:
# the name it gives that mode, the file its machine expects, the colour space
# its workflow uses, its own ceilings. Two shops both doing sublimation may
# want different files, and the client never has to know.
class PrinterTechnique < ApplicationRecord
  OUTPUT_FORMATS = %w[ svg png pdf ].freeze
  COLOR_SPACES = %w[ rgb cmyk ].freeze

  belongs_to :printer, inverse_of: :techniques

  normalizes :label, with: ->(l) { l.strip.presence }
  normalizes :note, with: ->(n) { n.strip.presence }

  # The list of keys is the catalogue's, never a copy: see PrintTechniques.
  validates :technique, presence: true,
                        inclusion: { in: ->(_) { PrintTechniques.keys } },
                        uniqueness: { scope: :printer_id }
  validates :output_format, inclusion: { in: OUTPUT_FORMATS }
  validates :color_space, inclusion: { in: COLOR_SPACES }
  validates :label, length: { maximum: 60 }, allow_nil: true
  validates :note, length: { maximum: 160 }, allow_nil: true
  validates :max_print_width_cm, :max_print_height_cm,
            numericality: { greater_than: 0, less_than_or_equal_to: 300 }, allow_nil: true

  # Techniques applied one colour at a time need a ceiling; the shop cannot say
  # what it can print without one. It is capped by the catalogue's own ceiling,
  # which is what the generator will accept anyway.
  validates :max_colors, presence: true, if: :limited_colors?
  validates :max_colors, numericality: {
    only_integer: true,
    greater_than: 0,
    less_than_or_equal_to: ->(record) { record.catalogue_max_colors },
    if: :limited_colors?
  }, allow_nil: true

  validate :colour_ceiling_belongs_to_counted_inks

  scope :primary_first, -> { order(primary: :desc, technique: :asc) }

  # The catalogue entry behind this row. Raises on an unknown key: that means a
  # stale catalogue or a renamed technique, not a visitor's input.
  def catalogue = PrintTechniques.fetch(technique)

  # The shop's own wording wins; the catalogue's French label is the default.
  def display_label = label.presence || catalogue.label

  def limited_colors? = technique.present? && PrintTechniques.find(technique)&.limited_colors?

  def catalogue_max_colors = PrintTechniques.find(technique)&.max_colors

  # Blank dimensions fall back to the shop-wide maximum on the listing.
  def effective_max_width_cm = max_print_width_cm || printer&.max_print_width_cm

  def effective_max_height_cm = max_print_height_cm || printer&.max_print_height_cm

  # Whether this setup can print a design with that many inks. The full rule —
  # technique, inks and size together — lives in PrinterCompatibility.
  def prints_inks?(count)
    return true unless limited_colors?

    max_colors.present? && count.present? && max_colors >= count
  end

  def prints_width?(width_cm)
    limit = effective_max_width_cm
    limit.blank? || width_cm.blank? || width_cm <= limit
  end

  private
    # A colour ceiling on DTF says nothing: the machine prints every colour at
    # once. Leaving it filled would show a limit the shop does not have.
    def colour_ceiling_belongs_to_counted_inks
      return if limited_colors? || max_colors.blank?

      errors.add(:max_colors, :present)
    end
end
