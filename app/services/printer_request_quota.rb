# How many print requests a workshop's plan includes this month, and how many
# it has used.
#
# Decided on 20/10/2026: the allowance counts requests, not generations. A
# workshop pays for real jobs coming in, not for a client trying fifteen ideas
# on a Sunday afternoon. A request counts when the workshop takes it on, and
# when it lets it expire without an answer — otherwise ignoring every request
# would spend nothing. It does not count when the client calls it off, nor
# when the workshop sets it aside as not worth quoting, up to a share of the
# month's requests (`declined_free_share`); past that share, a refusal counts
# like any other request.
#
# A request belongs to the month it was sent in, whenever it is answered.
#
# Reaching the ceiling blocks nothing: requests keep reaching the workshop,
# which is told once a month and offered Atelier+. Cutting a client off in
# mid-month would lose the workshop a job, and the platform its goodwill.
#
# The limit and the share are plan settings in config/settings.yml; a nil limit
# means unlimited.
class PrinterRequestQuota
  # The states that spend the allowance. `sent` is still undecided, `canceled`
  # is the client's doing; `declined` is counted apart, see #used.
  COUNTED_STATUSES = %w[ acknowledged quoted in_production completed expired ].freeze

  def self.for(printer) = new(printer)

  def initialize(printer)
    @printer = printer
  end

  # nil when there is no limit: no workshop, or a plan without one.
  def limit
    return nil if @printer.nil?

    plan = @printer.subscription&.plan
    return nil if plan.nil?

    settings.fetch(:monthly_print_requests, {})[plan.to_sym]
  end

  def limited? = !limit.nil?

  def used = counted + declined_over_share

  def remaining = limited? ? [ limit - used, 0 ].max : nil

  def reached? = limited? && used >= limit

  def exceeded? = limited? && used > limit

  # How many more requests the workshop may set aside this month without them
  # counting. The share is taken of the month's requests so far, so it grows
  # as they come in.
  def free_declines_left = [ free_declines - declined, 0 ].max

  # Tells the workshop once a month, the moment its allowance is used.
  def notify_if_reached!
    return unless reached?
    return if @printer.request_quota_notified_on.present? &&
              @printer.request_quota_notified_on >= month.begin.to_date

    @printer.update_column(:request_quota_notified_on, Time.zone.today)
    SubscriptionMailer.request_quota_reached(@printer).deliver_later
  end

  private
    def settings = Rails.application.config.tshirt.subscriptions

    def month = Time.zone.now.all_month

    # One query for the whole month, grouped by state.
    def counts
      @counts ||= if @printer.nil?
        {}
      else
        PrintRequest.where(printer_id: @printer.id, sent_at: month).group(:status).count
      end
    end

    def counted = counts.values_at(*COUNTED_STATUSES).sum(&:to_i)

    def declined = counts["declined"].to_i

    # Everything the workshop had to answer this month: what the client
    # called off never reached that point.
    def answerable = counts.sum { |status, count| status == "canceled" ? 0 : count }

    # Rationalized so that 0.3 of ten is three, not 2.9999….
    def free_declines = (answerable * settings.fetch(:declined_free_share).rationalize).floor

    def declined_over_share = [ declined - free_declines, 0 ].max
end
