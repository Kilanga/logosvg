class Design < ApplicationRecord
  include AASM

  STYLES = %w[ illustration logo mascotte badge ].freeze
  MODES = %w[ create variant refine ].freeze
  PRINT_FORMATS = %w[ svg png ].freeze

  belongs_to :user
  belongs_to :printer, optional: true
  belongs_to :parent, class_name: "Design", optional: true
  belongs_to :root, class_name: "Design", optional: true

  has_many :children, class_name: "Design", foreign_key: :parent_id,
           dependent: :nullify, inverse_of: :parent
  has_many :lineage, class_name: "Design", foreign_key: :root_id,
           dependent: :nullify, inverse_of: :root

  # The file the workshop prints — an SVG or a PNG, depending on the technique.
  # Never served to the client: see docs/SPEC.md, "Fichiers".
  has_one_attached :print_file
  # The raw image the model drew, kept for comparison and for the workshop.
  has_one_attached :source_png

  has_secure_token :token

  normalizes :prompt, with: ->(p) { p.strip.squeeze(" ") }

  validates :prompt, presence: true, length: { in: 3..300 }
  validates :style, inclusion: { in: STYLES }
  validates :mode, inclusion: { in: MODES }
  validates :technique, presence: true, inclusion: { in: ->(_) { PrintTechniques.keys } }
  validates :print_format, inclusion: { in: PRINT_FORMATS }, allow_nil: true
  validates :colors_requested, numericality: { in: 1..6 }, allow_nil: true
  validates :print_width_cm, numericality: { in: 3..60 }, allow_nil: true
  validates :instruction, length: { in: 3..200 }, allow_nil: true

  # The technique shaped the prompt, not only the output file: changing it after
  # the fact would describe a design nobody generated.
  validate :technique_is_frozen, on: :update

  scope :active, -> { where(deleted_at: nil) }
  scope :newest_first, -> { order(created_at: :desc) }
  scope :roots, -> { where(parent_id: nil) }

  # `pending` → `generating` → `ready` or `failed`. A failed design may be
  # started again and has consumed no quota; a ready one never changes.
  aasm column: :status, whiny_transitions: true do
    state :pending, initial: true
    state :generating
    state :ready
    state :failed

    event :start do
      transitions from: [ :pending, :failed ], to: :generating
    end

    event :succeed do
      transitions from: :generating, to: :ready
    end

    event :fail do
      transitions from: [ :pending, :generating ], to: :failed
      after { |message| self.error_message = message }
    end
  end

  # Public URLs carry the token, never the sequential id.
  def to_param = token

  def catalogue = PrintTechniques.fetch(technique)

  def technique_label = PrintTechniques.label_for(technique)

  # Vector output counts inks and paths; raster output counts pixels. Asking a
  # DTF design how many screens it needs is meaningless.
  def vector? = print_format == "svg" || (print_format.nil? && catalogue.vector?)

  def raster? = !vector?

  def in_progress? = pending? || generating?

  def lineage_root = root || self

  def soft_delete! = update!(deleted_at: Time.current)

  def active? = deleted_at.nil?

  # What the directory needs to answer "who can print this?".
  def compatibility_with(printer)
    PrinterCompatibility.call(printer: printer, technique: technique,
                              inks_count: inks_count, print_width_cm: print_width_cm)
  end

  private
    def technique_is_frozen
      errors.add(:technique, :frozen_after_creation) if technique_changed?
    end
end
