class Subscription < ApplicationRecord
  # Not a state machine in the AASM sense: nothing here decides anything. The
  # status is Stripe's word, copied in by webhooks, and the only rule this
  # model owns is what it means for a listing's visibility.
  #
  # See docs/SPEC.md, "Abonnements imprimeurs".
  PLANS = %w[ listing atelier_plus ].freeze
  STATUSES = %w[ incomplete trialing active past_due canceled ].freeze

  # The two that pay for a visible listing outright.
  PAYING_STATUSES = %w[ trialing active ].freeze

  belongs_to :printer

  validates :plan, inclusion: { in: PLANS }
  validates :status, inclusion: { in: STATUSES }

  scope :paying, -> { where(status: PAYING_STATUSES) }

  STATUSES.each do |value|
    define_method("#{value}?") { status == value }
  end

  PLANS.each do |value|
    define_method("#{value}?") { plan == value }
  end

  # A failed payment does not pull a shop off the directory the same day: it
  # keeps its listing for a few days while it sorts the card out.
  def within_grace?
    return false unless past_due?
    return true if past_due_since.nil?

    past_due_since > grace_days.days.ago
  end

  def visible? = PAYING_STATUSES.include?(status) || within_grace?

  # When the listing goes dark, for the email that warns about it.
  def hidden_from
    return nil unless past_due?

    (past_due_since || Time.current) + grace_days.days
  end

  # Atelier+ buys the highlight, the brand colour on the creation screen and
  # the link statistics — and only while it is actually being paid for.
  def featured? = atelier_plus? && visible?

  # The SQL behind `Printer.listed`. Written once, here, so the directory, the
  # shop page and every compatibility check ask the same question.
  def self.visible_printer_ids
    grace_mark = Rails.application.config.tshirt.subscriptions[:past_due_grace_days].days.ago

    where(status: PAYING_STATUSES)
      .or(where(status: "past_due").where(past_due_since: grace_mark..))
      .or(where(status: "past_due").where(past_due_since: nil))
      .select(:printer_id)
  end

  private
    def grace_days = Rails.application.config.tshirt.subscriptions[:past_due_grace_days]
end
