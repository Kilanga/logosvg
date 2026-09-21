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
    end

    private
      def alarming_ids
        threshold = Rails.application.config.tshirt.reviews[:return_rate_alert_threshold]

        @return_rates.select { |_, rate| rate >= threshold }.keys
      end

      # Work past its deadline, or delivered and plainly unanswered.
      def disputes_count
        overdue = Review.where(status: "in_progress").where(due_at: ...Time.current).count
        stale = Review.where(status: "delivered")
                      .where(delivered_at: ...auto_accept_days.days.ago).count

        overdue + stale
      end

      def auto_accept_days = Rails.application.config.tshirt.reviews[:auto_accept_days]
  end
end
