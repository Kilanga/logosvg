# How many generations a workshop's clients may run this month, through it.
#
# Decided on 06/10/2026: the Référencement plan includes 100 generations a
# month, Atelier+ is unlimited. A generation is a client's click on a design
# carrying the workshop — a creation, a retouch, a request for other versions —
# however many proposals it drew: they share a batch token. Failed ones are not
# counted. The per-client
# daily allowance (GenerationQuota) applies on top, whatever the plan.
#
# The limit is a plan setting in config/settings.yml; nil means unlimited.
class PrinterGenerationQuota
  def self.for(printer) = new(printer)

  def initialize(printer)
    @printer = printer
  end

  # nil when there is no limit: no workshop in context, or a plan without one.
  def limit
    return nil if @printer.nil?

    plan = @printer.subscription&.plan
    return nil if plan.nil?

    Rails.application.config.tshirt.subscriptions.fetch(:monthly_generations, {})[plan.to_sym]
  end

  def limited? = !limit.nil?

  def used
    return 0 if @printer.nil?

    # A client's own image put in format draws nothing: it is not a generation.
    Design.where(printer_id: @printer.id, created_at: month)
          .where.not(status: "failed").where.not(mode: "upload")
          .distinct.count(Arel.sql("COALESCE(designs.batch_token, designs.token)"))
  end

  def remaining = limited? ? [ limit - used, 0 ].max : nil

  # Room for `count` more clicks.
  def allows?(count = 1) = !limited? || used + count <= limit

  def exceeded? = !allows?

  # Tells the workshop once a month, the moment its clients hit the ceiling,
  # rather than once per refused client.
  def notify_if_reached!
    return unless limited? && used >= limit
    return if @printer.generation_quota_notified_on.present? &&
              @printer.generation_quota_notified_on >= month.begin.to_date

    @printer.update_column(:generation_quota_notified_on, Time.zone.today)
    SubscriptionMailer.generation_quota_reached(@printer).deliver_later
  end

  private
    def month = Time.zone.now.all_month
end
