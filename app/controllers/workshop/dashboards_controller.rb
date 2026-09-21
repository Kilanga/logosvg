module Workshop
  # Workshop dashboard: where the listing stands, the month's figures, the last
  # requests, the sharing link and the subscription.
  class DashboardsController < BaseController
    # Every list here comes from this shop's own associations; the space check
    # in SpaceController is the authorization.
    skip_after_action :verify_policy_scoped

    def show
      @printer = current_printer
      @subscription = @printer&.subscription
      @print_requests = recent_requests
      @month = month_figures
    end

    private
      def recent_requests
        return PrintRequest.none if @printer.nil?

        @printer.print_requests.newest_first.limit(5)
                .includes(:client, design: :print_file_attachment)
      end

      # One pass over the month's rows rather than three counting queries.
      def month_figures
        return { requests: 0, to_confirm: 0, garments: 0 } if @printer.nil?

        rows = @printer.print_requests.where(created_at: Time.current.all_month)
                       .pluck(:status, :total_qty)

        { requests: rows.size,
          to_confirm: rows.count { |status, _| status == "sent" },
          garments: rows.sum { |_, quantity| quantity.to_i } }
      end
  end
end
