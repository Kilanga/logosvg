class PrinterTechnique < ApplicationRecord
  enum :technique,
       { screen_printing: 0, dtf: 1, dtg: 2, flex: 3, embroidery: 4 },
       validate: true

  # Techniques that reproduce a full-colour image: every ink is printed at once,
  # so the number of colours in the design does not matter.
  UNLIMITED_COLOURS = %w[ dtf dtg ].freeze

  FORMATS = %w[ svg pdf eps png ].freeze

  belongs_to :printer, inverse_of: :techniques

  validates :technique, uniqueness: { scope: :printer_id }
  validates :accepted_formats, inclusion: { in: FORMATS }, allow_blank: true

  # Screen printing, flex and embroidery are applied colour by colour: without a
  # ceiling the shop cannot say what it is able to print.
  validates :max_colors, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 12 },
                         unless: :unlimited_colours?

  def unlimited_colours? = UNLIMITED_COLOURS.include?(technique)

  # Whether this technique can print a design with the given ink count.
  # The rule proper lives in PrinterCompatibility, built in step 3; this is the
  # per-technique half of it.
  def prints?(inks_count)
    return false unless accepted_formats.include?("svg")
    return true if unlimited_colours?

    max_colors.present? && inks_count.present? && max_colors >= inks_count
  end
end
