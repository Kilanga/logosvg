# How hard the generation machine is working (decided on 16/10/2026, when the
# reprises stopped counting against the creations of the day).
#
# Counted in images, not in clicks: the machine draws every proposal one after
# the other, so three proposals are three times the work. Deleted designs are
# counted too — the machine drew them all the same. A design dropped onto the
# platform (upload) or made by a designer (reviewed) never reached the model.
#
# The wait is the time between the client's click and the image, as the client
# lived it: it grows with the queue before it shows anywhere else.
class GenerationLoad
  DRAWN = %w[ create variant refine ].freeze

  Day = Data.define(:date, :images)

  def self.alert_wait_seconds = Rails.application.config.tshirt.generation.fetch(:load_alert_wait_seconds)

  def initialize(now: Time.current)
    @now = now
  end

  def images_today = today.count

  def creations_today = today.where(mode: "create").count

  def reprises_today = today.where(mode: %w[ variant refine ]).count

  def failed_today = today.where(status: "failed").count

  # The busiest hour of the day, as [hour, images], or nil on a quiet day.
  # Counted here rather than in SQL: a day is a few hundred images at most,
  # and the hour is the one on the administrator's clock.
  def busiest_hour_today
    today.pluck(:created_at).group_by { |at| at.in_time_zone.hour }
         .map { |hour, ats| [ hour, ats.size ] }.max_by { |hour, size| [ size, -hour ] }
  end

  # Mean and longest wait today, in seconds, over the images that came back.
  def mean_wait_today = waits.average(wait_sql)&.to_f&.round

  def longest_wait_today = waits.maximum(wait_sql)&.to_f&.round

  def slow? = mean_wait_today.to_i > self.class.alert_wait_seconds

  # The last seven days, oldest first, a day with nothing included.
  def last_week
    counts = drawn.where(created_at: week_start..@now)
                  .group(Arel.sql("(created_at AT TIME ZONE 'UTC' AT TIME ZONE '#{zone}')::date")).count
    (0..6).map do |back|
      date = @now.to_date - (6 - back)
      Day.new(date: date, images: counts[date].to_i)
    end
  end

  private
    def drawn = Design.where(mode: DRAWN)

    def today = drawn.where(created_at: @now.beginning_of_day..@now)

    def waits = today.where.not(finished_at: nil)

    def wait_sql = Arel.sql("EXTRACT(EPOCH FROM finished_at - created_at)")

    def week_start = (@now.to_date - 6).in_time_zone.beginning_of_day

    def zone = Time.zone.tzinfo.name
end
