class Design < ApplicationRecord
  include AASM

  STYLES = %w[ illustration logo mascotte badge ].freeze
  # `reviewed`: a designer's accepted delivery, made a design of its own so it
  # can be sent to a workshop. See CreateReviewedDesign.
  MODES = %w[ create variant refine reviewed ].freeze
  PRINT_FORMATS = %w[ svg png ].freeze

  belongs_to :user
  belongs_to :printer, optional: true
  belongs_to :parent, class_name: "Design", optional: true
  belongs_to :root, class_name: "Design", optional: true
  belongs_to :source_review, class_name: "Review", optional: true

  has_many :children, class_name: "Design", foreign_key: :parent_id,
           dependent: :nullify, inverse_of: :parent
  has_many :lineage, class_name: "Design", foreign_key: :root_id,
           dependent: :nullify, inverse_of: :root

  # A sent request keeps its own copies of the files, so it outlives the design
  # it came from — but it is never orphaned while the design is still there.
  has_many :print_requests, dependent: :restrict_with_error, inverse_of: :design
  has_many :reviews, dependent: :restrict_with_error, inverse_of: :design

  # The file the workshop prints — an SVG or a PNG, depending on the technique.
  # Never served to the client: see docs/SPEC.md, "Fichiers".
  has_one_attached :print_file
  # The raw image the model drew, kept for comparison and for the workshop.
  has_one_attached :source_png
  # The client's own image the generation started from, when there was one —
  # already re-encoded by ReferenceImage. Optional.
  has_one_attached :reference_image

  # Ticked on the form: the client may use the image, and it shows nobody
  # identifiable without their consent. Asked only when an image is sent.
  attribute :reference_rights_confirmed, :boolean, default: false
  validate :reference_image_rights_confirmed, on: :create

  has_secure_token :token

  normalizes :prompt, with: ->(p) { p.strip.squeeze(" ") }

  validates :prompt, presence: true, length: { in: 3..300 }
  validates :style, inclusion: { in: STYLES }
  validates :mode, inclusion: { in: MODES }
  validates :technique, presence: true, inclusion: { in: ->(_) { PrintTechniques.keys } }
  validates :print_format, inclusion: { in: PRINT_FORMATS }, allow_nil: true
  validates :colors_requested, numericality: { in: 1..6 }, allow_nil: true
  # Asked of the client for every technique, not only the raster ones: a chest
  # logo and a back print are not the same job, and the width is what decides
  # which workshops can print the result at all.
  validates :print_width_cm, numericality: { in: 3..60 }
  validates :instruction, length: { in: 3..200 }, allow_nil: true

  # The technique shaped the prompt, not only the output file: changing it after
  # the fact would describe a design nobody generated.
  validate :technique_is_frozen, on: :update

  # Refused here rather than by the service: a prompt turned away on this side
  # costs no allowance, reaches no other machine, and says so in French.
  validate :prompt_avoids_blocked_terms, on: :create

  scope :active, -> { where(deleted_at: nil) }
  scope :newest_first, -> { order(created_at: :desc) }
  scope :roots, -> { where(parent_id: nil) }
  # Not one of several proposals still on offer: a design the client has.
  scope :kept, -> { where(batch_token: nil).or(where.not(chosen_at: nil)) }

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

  def reviewed? = mode == "reviewed"

  # Reprises already spent on this lineage, counted by the application.
  #
  # The service counts them too, but in memory: every time its machine is
  # switched off, the count went back to zero and the client got three more
  # goes. A reprise is a client's action, not an image — a refinement is one,
  # and a click on "other versions" is one whatever number of variants it made
  # (they share a batch token). Failed attempts cost nothing; deleted ones
  # still count.
  #
  # Since October 2026 every click draws several proposals, refinements
  # included: whatever its mode, a batch is one reprise.
  def refinements_used
    children = Design.where(root_id: lineage_root_id).where.not(status: "failed")
    batches = children.where.not(batch_token: nil).distinct.count(:batch_token)
    single = children.where(batch_token: nil).where.not(mode: "variant").count

    batches + single + legacy_variant_clicks(children)
  end

  # One of the proposals of a click, before the client has kept one. Nothing
  # goes further from it — no reprise, no workshop, no designer — until then.
  def awaiting_choice? = batch_token.present? && chosen_at.nil?

  # The proposals drawn by the same click, this one included, oldest first.
  def proposals
    return Design.where(id: id) if batch_token.blank?

    Design.active.where(batch_token: batch_token).order(:id)
  end

  def refinements_remaining
    [ Rails.application.config.tshirt.generation[:max_refinements] - refinements_used, 0 ].max
  end

  def catalogue = PrintTechniques.fetch(technique)

  def technique_label = PrintTechniques.label_for(technique)

  # Vector output counts inks and paths; raster output counts pixels. Asking a
  # DTF design how many screens it needs is meaningless.
  def vector? = print_format == "svg" || (print_format.nil? && catalogue.vector?)

  def raster? = !vector?

  def in_progress? = pending? || generating?

  def lineage_root = root || self

  # L'identifiant de la racine sans charger la racine. Un enfant se rattache à
  # la lignée par une clé étrangère : aller chercher l'enregistrement pour lire
  # son id, c'est une requête de plus et, sur un design rendu par un travail de
  # fond, un chargement paresseux qui lève en développement.
  def lineage_root_id = root_id || id

  def soft_delete! = update!(deleted_at: Time.current)

  def active? = deleted_at.nil?

  # What the directory needs to answer "who can print this?".
  def compatibility_with(printer)
    PrinterCompatibility.call(printer: printer, technique: technique,
                              inks_count: inks_count, print_width_cm: print_width_cm)
  end

  private
    def reference_image_rights_confirmed
      return unless reference_image.attached?
      return if reference_rights_confirmed

      errors.add(:reference_rights_confirmed, :accepted)
    end

    # Variants made before batch tokens existed: those of one click share a
    # parent and were saved in the same transaction, so the same minute.
    def legacy_variant_clicks(children)
      children.where(mode: "variant", batch_token: nil)
              .pluck(:parent_id, :created_at)
              .map { |parent_id, created_at| [ parent_id, created_at.change(sec: 0) ] }
              .uniq.size
    end

    def technique_is_frozen
      errors.add(:technique, :frozen_after_creation) if technique_changed?
    end

    def prompt_avoids_blocked_terms
      term = BlockedTerm.matching(prompt)
      return if term.nil?

      BlockedTerm.record_hit!(term)
      errors.add(:prompt, :blocked_term, term: term)
    end
end
