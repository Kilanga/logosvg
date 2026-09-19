# How many designs a client may generate today.
#
# Counted in its own table rather than by counting designs: a failed generation
# must not consume an attempt, and deleting a design must not hand one back.
#
# The daily allowance is a configured value, not a constant buried here — see
# config/settings.yml.
class GenerationQuota
  def self.per_day = Rails.application.config.tshirt.generation[:quota_per_day]

  def self.for(user) = new(user)

  def initialize(user)
    @user = user
  end

  def used = counter&.count.to_i

  def remaining = [ self.class.per_day - used, 0 ].max

  def exceeded? = remaining.zero?

  # Consumes one attempt, atomically. An upsert rather than find-then-increment:
  # two submissions in the same instant would otherwise both read the same count
  # and both be allowed through.
  #
  # Returns false when the allowance is already spent, so the caller can refuse
  # without a second round trip.
  def consume!
    return false if exceeded?

    GenerationCounter.upsert(
      { user_id: @user.id, day: today, count: 1, created_at: Time.current, updated_at: Time.current },
      unique_by: %i[ user_id day ],
      on_duplicate: Arel.sql("count = generation_counters.count + 1, updated_at = EXCLUDED.updated_at")
    )

    @counter = nil
    true
  end

  # Gives an attempt back. Used when a generation never reached the service, so
  # the client is not billed an attempt for our own failure.
  def refund!
    return if counter.nil? || counter.count.zero?

    GenerationCounter.where(id: counter.id).update_all("count = GREATEST(count - 1, 0)")
    @counter = nil
  end

  private
    def today = Time.zone.today

    def counter
      return @counter if defined?(@counter) && @counter

      @counter = GenerationCounter.find_by(user: @user, day: today)
    end
end
