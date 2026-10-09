class Review < ApplicationRecord
  include AASM

  ASSIGNMENT_MODES = %w[ chosen first_available ].freeze

  # How many designers in a row may hand the review back at a proposed level
  # before the client is left with only the proposal or a refund. See
  # "pick_new_designer" below and docs/SPEC.md, "Renvoi au client par le
  # graphiste".
  MAX_DESIGNER_REFUSALS = 2

  # Why a designer hands the job back. The first two carry a proposal; the last
  # three do not — the review is cancelled and refunded outright.
  RETURN_REASONS = %w[ level_too_low level_too_high unusable_design forbidden_content other ].freeze
  PROPOSING_REASONS = %w[ level_too_low level_too_high ].freeze

  # Why a client says a delivery is not right. Decided on 08/10/2026: once per
  # review, on a delivered version, and it stops the automatic acceptance.
  DISPUTE_REASONS = %w[ not_as_requested file_defect other ].freeze

  # The structured brief, in the order the client fills it. `change` is the
  # one that is required: a designer cannot work from nothing.
  BRIEF_KEYS = %w[ change keep text colors ].freeze

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
  validates :dispute_reason, inclusion: { in: DISPUTE_REASONS }, allow_nil: true
  validates :designer_payout_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  # Asked of a client filling the form, not of every row created elsewhere
  # (an administrator's tools, the seeds): set by the controller.
  attribute :brief_required, :boolean, default: false
  validate :brief_says_what_to_change, on: :create, if: :brief_required

  # Kept to the four known points, stripped, and composed into `client_brief`,
  # which every screen, email and export already reads.
  before_validation :tidy_brief
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
    state :disputed
    state :accepted
    state :canceled

    # A custom job is quoted by the designer and settled between the designer
    # and the client, outside the platform (decided on 06/10/2026): nothing to
    # pay here, so it goes straight to the designers.
    event :open_without_payment do
      transitions from: :awaiting_payment, to: :queued, guard: :off_platform?
      after { self.queued_at = Time.current }
    end

    # Stripe's webhook, never a button.
    event :pay do
      transitions from: :awaiting_payment, to: :queued
      after { self.paid_at = self.queued_at = Time.current }
    end

    # A designer takes it. The guard is the point of step 7: nothing reaches
    # someone who cannot be paid.
    event :claim do
      transitions from: :queued, to: :in_progress, guard: :claimable?
    end

    # Every delivery starts the client's week again, reminders included.
    event :deliver do
      transitions from: :in_progress, to: :delivered
      after { restart_client_period }
      after do
        self.delivered_at = Time.current
        self.acceptance_reminders_sent = 0
      end
    end

    # The client asks for another go, within what they paid for.
    event :request_revision do
      transitions from: :delivered, to: :in_progress, guard: :revisions_left?
      after { self.revisions_used += 1 }
    end

    # By the client, or by the sweep seven days after the last delivery — or,
    # from a dispute, by the client satisfied after all or by an administrator
    # who decides the designer is paid.
    event :accept do
      transitions from: [ :delivered, :disputed ], to: :accepted
      after { self.accepted_at = Time.current }
    end

    # The client says the delivery does not do what was asked. Once per
    # review: the automatic acceptance stops, and the designer and an
    # administrator are told.
    event :dispute do
      transitions from: :delivered, to: :disputed, guard: :disputable?
      after { self.disputed_at = Time.current }
    end

    # The designer offered to put it right at no cost, and the client took
    # the offer: one more go than the level included.
    event :accept_fix do
      transitions from: :disputed, to: :in_progress, guard: :fix_offered?
      after do
        self.revisions_included += 1
        self.revisions_used += 1
        self.due_at = Time.current + review_level.turnaround_hours.hours
      end
    end

    # The client changed their mind. The delivery is back on the table with a
    # fresh week to answer, as if it had just arrived.
    event :withdraw_dispute do
      transitions from: :disputed, to: :delivered
      after do
        self.delivered_at = Time.current
        self.acceptance_reminders_sent = 0
      end
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
      after { self.queued_at = Time.current }
    end

    # The client did not want to pay the proposed difference, but is not ready
    # to give up either: a new designer, picked by the client exactly as the
    # first one was, takes it at the level and price already paid. Capped at
    # MAX_DESIGNER_REFUSALS — past that, only the proposal or a refund remain.
    event :pick_new_designer do
      transitions from: :returned_to_client, to: :queued, guard: :reassignable?
      after { self.queued_at = Time.current }
    end

    # Refused, or simply never answered.
    event :decline_proposal do
      transitions from: :returned_to_client, to: :canceled
      after do
        self.canceled_at = Time.current
        resume_client_period
      end
    end

    # A custom job the designer and the client finished between themselves,
    # with or without a file handed back here.
    event :finish_off_platform do
      transitions from: [ :in_progress, :delivered ], to: :accepted, guard: :off_platform?
      after do
        self.accepted_at = Time.current
        restart_client_period
      end
    end

    # Abandoned before payment, or settled by an administrator.
    event :cancel do
      transitions from: [ :awaiting_payment, :queued, :in_progress, :delivered,
                          :returned_to_client, :disputed ], to: :canceled
      after do
        resume_client_period
        self.canceled_at = Time.current
      end
    end
  end

  def to_param = token

  # --- The client's thirty days with the shop (decided on 09/10/2026) --------

  # The designer has delivered: thirty fresh days with the shop the design was
  # made for — as long as the client still belongs to it.
  def restart_client_period
    printer_id = Design.where(id: design_id).pick(:printer_id)
    User.extend_attachment!(client_id: client_id, printer_id: printer_id) if printer_id
  end

  # Ended without a delivery: the time the review held the period still is
  # given back. Nothing was held before the review went into the queue.
  def resume_client_period
    held_since = paid_at || queued_at
    printer_id = Design.where(id: design_id).pick(:printer_id)
    return if held_since.nil? || printer_id.nil? || aasm.from_state == :awaiting_payment

    User.resume_attachment!(client_id: client_id, printer_id: printer_id,
                            paused_seconds: Time.current - held_since)
  end

  def chosen? = assignment_mode == "chosen"

  # Quoted, arranged and paid between the designer and the client: the
  # platform only introduces them and keeps track.
  def off_platform? = read_association(:review_level)&.quoted? || false

  def first_available? = assignment_mode == "first_available"

  def revisions_left = [ revisions_included - revisions_used, 0 ].max

  def revisions_left? = revisions_left.positive?

  # A paid review, delivered, never disputed before.
  def disputable? = delivered? && disputed_at.nil? && !off_platform?

  def fix_offered? = fix_offered_at.present?

  # The points of the brief the client actually filled, in order.
  def brief_items = BRIEF_KEYS.filter_map { |key| [ key, brief[key] ] if brief[key].present? }

  # What the designer is paid: the full share, or what an administrator
  # decided when splitting.
  def payout_cents = designer_payout_cents || designer_share_cents

  # The designer's share of what the platform keeps after a partial refund:
  # the commission applies to what is paid, at the review's own rate.
  def payout_after_refund(refund_cents)
    kept = [ price_cents - refunded_cents - refund_cents, 0 ].max
    return 0 if price_cents.zero?

    kept - (kept * platform_fee_cents / price_cents.to_f).round
  end

  def latest_version = versions.last

  def delivered_any? = versions.any?

  def open? = %w[ queued in_progress delivered returned_to_client disputed ].include?(status)

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

  # Who the client could pick next: still listed, still payable, still takes
  # this level, and not someone who has already handed this very review back.
  def reassignment_candidates
    DesignerProfile.listed.accepting.offering(review_level).by_reputation
                   .where.not(id: excluded_from_reassignment)
  end

  # What the client pays or is refunded when they take a proposal. Positive
  # means they owe the difference; negative means it comes back to them.
  def proposal_difference_cents
    return 0 if proposed_amount_cents.nil?

    proposed_amount_cents - price_cents
  end

  # A proposal to go custom costs nothing here: the whole price paid comes
  # back, and the job is quoted outside the platform.
  def proposed_amount_cents
    level = read_association(:proposed_level)
    return 0 if level&.quoted?
    return proposed_price_cents if proposed_price_cents.present?

    level&.price_cents
  end

  def designer_share_cents = price_cents - platform_fee_cents

  # The chosen designer had 12 hours and did not take it. The client then picks
  # what happens next — see docs/SPEC.md, "Graphiste choisi indisponible".
  def chosen_designer_silent?
    return false unless queued? && chosen? && designer_profile_id.present?

    # A custom job is never paid here: its clock starts when it was asked for.
    since = paid_at || (created_at if off_platform?)
    return false if since.nil?

    since <= settings[:designer_claim_timeout_hours].hours.ago
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

    def tidy_brief
      raw = (brief || {}).to_h.stringify_keys.slice(*BRIEF_KEYS)
      self.brief = raw.transform_values { |value| value.to_s.strip.first(1000) }.compact_blank
      return if brief.empty?

      self.client_brief = brief_items.map do |key, value|
        "#{I18n.t("reviews.brief.#{key}")} : #{value}"
      end.join("\n")
    end

    def brief_says_what_to_change
      # A free-text brief (older forms, the API of tests) still counts; a
      # structured one must say what to change.
      return if brief.empty? ? client_brief.present? : brief["change"].present?

      errors.add(:brief, :what_to_change)
    end

    def claimable? = claimable_by?(designer_profile)

    def reassignable? = proposal? && designer_refusals_count < MAX_DESIGNER_REFUSALS

    def excluded_from_reassignment = refused_designer_profile_ids + [ designer_profile_id ].compact

    def chosen_designer_takes_this_level
      return if designer_profile.accepts?(review_level)

      errors.add(:designer_profile, :does_not_offer_level)
    end
end
