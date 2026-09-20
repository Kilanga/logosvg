class Review < ApplicationRecord
  include AASM

  ASSIGNMENT_MODES = %w[ chosen first_available ].freeze

  # Why a designer hands the job back. The first two carry a proposal; the last
  # three do not — the review is cancelled and refunded outright.
  RETURN_REASONS = %w[ level_too_low level_too_high unusable_design forbidden_content other ].freeze
  PROPOSING_REASONS = %w[ level_too_low level_too_high ].freeze

  belongs_to :design
  belongs_to :client, class_name: "User"
  belongs_to :designer_profile, optional: true
  belongs_to :review_level
  belongs_to :proposed_level, class_name: "ReviewLevel", optional: true
  # Who settled a dispute, when the two sides could not.
  belongs_to :settled_by, class_name: "User", optional: true

  has_many :versions, -> { order(:number) }, class_name: "ReviewVersion",
           dependent: :destroy, inverse_of: :review
  has_many :messages, -> { order(:created_at) }, class_name: "ReviewMessage",
           dependent: :destroy, inverse_of: :review

  has_secure_token :token

  validates :assignment_mode, inclusion: { in: ASSIGNMENT_MODES }
  validates :price_cents, :platform_fee_cents, :revisions_used, :revisions_included,
            numericality: { greater_than_or_equal_to: 0 }
  validates :return_reason_code, inclusion: { in: RETURN_REASONS }, allow_nil: true
  validates :rating, numericality: { in: 1..5 }, allow_nil: true
  validate :chosen_designer_takes_this_level, if: -> { chosen? && designer_profile.present? }

  scope :newest_first, -> { order(created_at: :desc) }
  scope :open_for_designer, -> { where(status: %w[ queued in_progress delivered ]) }
  scope :awaiting_claim, -> { where(status: "queued") }

  # The whole life of a review. Every transition here is one somebody can
  # trigger; the guards say who and when. See docs/SPEC.md, "Revue graphiste".
  aasm column: :status, whiny_transitions: true do
    state :awaiting_payment, initial: true
    state :queued
    state :in_progress
    state :delivered
    state :returned_to_client
    state :accepted
    state :canceled

    # Stripe's webhook, never a button.
    event :pay do
      transitions from: :awaiting_payment, to: :queued
      after { self.paid_at = Time.current }
    end

    # A designer takes it. The guard is the point of step 7: nothing reaches
    # someone who cannot be paid.
    event :claim do
      transitions from: :queued, to: :in_progress, guard: :claimable?
    end

    event :deliver do
      transitions from: :in_progress, to: :delivered
      after { self.delivered_at = Time.current }
    end

    # The client asks for another go, within what they paid for.
    event :request_revision do
      transitions from: :delivered, to: :in_progress, guard: :revisions_left?
      after { self.revisions_used += 1 }
    end

    # By the client, or by the sweep seven days after the last delivery.
    event :accept do
      transitions from: :delivered, to: :accepted
      after { self.accepted_at = Time.current }
    end

    # Before any delivery, once per review, and the work done is not billed.
    event :return_to_client do
      transitions from: [ :queued, :in_progress ], to: :returned_to_client,
                  guard: :returnable?
      after { self.returned_at = Time.current }
    end

    # The client took the designer's proposal: back in the queue at the new
    # level, with the same designer if they offered to do it.
    event :accept_proposal do
      transitions from: :returned_to_client, to: :queued, guard: :proposal_open?
    end

    # Refused, or simply never answered.
    event :decline_proposal do
      transitions from: :returned_to_client, to: :canceled
      after { self.canceled_at = Time.current }
    end

    # Abandoned before payment, or settled by an administrator.
    event :cancel do
      transitions from: [ :awaiting_payment, :queued, :in_progress, :delivered,
                          :returned_to_client ], to: :canceled
      after { self.canceled_at = Time.current }
    end
  end

  def to_param = token

  def chosen? = assignment_mode == "chosen"

  def first_available? = assignment_mode == "first_available"

  def revisions_left = [ revisions_included - revisions_used, 0 ].max

  def revisions_left? = revisions_left.positive?

  def latest_version = versions.last

  def delivered_any? = versions.any?

  def open? = %w[ queued in_progress delivered returned_to_client ].include?(status)

  def settled? = %w[ accepted canceled ].include?(status)

  # A designer may take this review: they accept the level, they can be paid,
  # and — when the client picked them — they are the one picked.
  def claimable_by?(profile)
    return false unless queued?
    return false unless profile&.can_take_work?
    return false unless profile.accepts?(review_level)
    return false if chosen? && designer_profile_id.present? && designer_profile_id != profile.id

    true
  end

  # Once per review, and never after a version has been handed over.
  def returnable? = returned_at.nil? && !delivered_any?

  def proposal_open? = proposal_expires_at.present? && proposal_expires_at.future?

  def proposal? = PROPOSING_REASONS.include?(return_reason_code)

  # What the client pays or is refunded when they take a proposal. Positive
  # means they owe the difference; negative means it comes back to them.
  def proposal_difference_cents
    return 0 if proposed_amount_cents.nil?

    proposed_amount_cents - price_cents
  end

  def proposed_amount_cents
    return proposed_price_cents if proposed_price_cents.present?

    proposed_level&.price_cents
  end

  def designer_share_cents = price_cents - platform_fee_cents

  # The chosen designer had 12 hours and did not take it. The client then picks
  # what happens next — see docs/SPEC.md, "Graphiste choisi indisponible".
  def chosen_designer_silent?
    return false unless queued? && chosen? && designer_profile_id.present?
    return false if paid_at.nil?

    paid_at <= settings[:designer_claim_timeout_hours].hours.ago
  end

  def auto_accept_due?
    delivered? && delivered_at.present? &&
      delivered_at <= settings[:auto_accept_days].days.ago
  end

  def proposal_expired? = returned_to_client? && proposal_expires_at.present? && proposal_expires_at.past?

  def overdue? = due_at.present? && due_at.past? && %w[ in_progress ].include?(status)

  # Red under six hours, as the spec asks: it is the designer's own deadline.
  def due_soon? = due_at.present? && due_at.future? && due_at <= 6.hours.from_now

  private
    def settings = Rails.application.config.tshirt.reviews

    def claimable? = claimable_by?(designer_profile)

    def chosen_designer_takes_this_level
      return if designer_profile.accepts?(review_level)

      errors.add(:designer_profile, :does_not_offer_level)
    end
end
