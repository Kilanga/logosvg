# One row per Stripe event id, ever.
#
# Stripe retries deliveries freely — on a timeout, on a 500, sometimes simply
# twice. Recording the id before acting, behind a unique index, is what makes
# handling a webhook safe to repeat.
class StripeEvent < ApplicationRecord
  # Uniqueness is the database's job here, not a validation's. A validation
  # reads the table and then writes, which two deliveries arriving together
  # both pass — and it raises before the index ever gets the chance to say no.
  validates :stripe_id, presence: true
  validates :event_type, presence: true

  scope :unprocessed, -> { where(processed_at: nil) }

  # Claims this event for processing, or returns nil if it has been seen
  # before. The insert is the lock: two webhook deliveries arriving at once
  # cannot both win, because the unique index will not allow the second row.
  def self.claim(id:, type:)
    create!(stripe_id: id, event_type: type)
  rescue ActiveRecord::RecordNotUnique
    nil
  end

  def processed! = update!(processed_at: Time.current, error_message: nil)

  # Kept rather than deleted: an event that failed is worth finding again.
  def failed!(error) = update!(error_message: error.to_s.truncate(1000))
end
