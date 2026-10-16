module Admin
  # What is waiting on an administrator, and nothing else.
  #
  # The counts are the point: an administrator opens this to find out whether
  # anything needs them, not to read figures.
  class DashboardsController < BaseController
    skip_after_action :verify_policy_scoped

    def show
      @waiting = {
        printers: Printer.pending_review.count,
        designers: DesignerProfile.where(status: "pending_review").count,
        disputes: disputes_count
      }

      # Designers handing work back more often than the platform expects. The
      # rates are computed for all of them at once — asking each profile in
      # turn cost two queries apiece.
      @return_rates = DesignerProfile.return_rates(DesignerProfile.listed)
      @returning = DesignerProfile.listed
                                  .where(id: alarming_ids)
                                  .order(:display_name)

      # Designers whose disputes keep ending with the client refunded.
      @lost_disputes = DesignerProfile.lost_disputes(DesignerProfile.listed)
      @disputing = DesignerProfile.listed
                                  .where(id: @lost_disputes.select { |_, count| count >= dispute_alert_count }.keys)
                                  .order(:display_name)

      # The Brevo plan's 300 a day, all the site's emails included (decided on
      # 10/10/2026): how far today has gone, and what could not leave at all.
      @mail_today = MailDeliveryDay.today
      @mail_failed = MailDeliveryDay.where(day: 6.days.ago.to_date..).sum(:failed_count)

      # What the generation machine drew today, and how long clients waited
      # (decided on 16/10/2026, when the reprises stopped counting against the
      # creations of the day).
      @load = GenerationLoad.new
    end

    private
      def alarming_ids
        threshold = Rails.application.config.tshirt.reviews[:return_rate_alert_threshold]

        @return_rates.select { |_, rate| rate >= threshold }.keys
      end

      def dispute_alert_count = Rails.application.config.tshirt.reviews[:dispute_alert_count]

      # Disputes opened by a client, work past its deadline, or delivered and
      # plainly unanswered.
      def disputes_count
        overdue = Review.where(status: "disputed")
                        .or(Review.where(status: "in_progress").where(due_at: ...Time.current)).count
        stale = Review.where(status: "delivered")
                      .where(delivered_at: ...auto_accept_days.days.ago).count

        overdue + stale
      end

      def auto_accept_days = Rails.application.config.tshirt.reviews[:auto_accept_days]
  end
end
