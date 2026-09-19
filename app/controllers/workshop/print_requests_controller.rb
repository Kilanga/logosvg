module Workshop
  # The orders a shop has received, and how it moves them along.
  class PrintRequestsController < BaseController
    before_action :set_print_request, only: %i[ show update ]

    STATUS_FILTERS = %w[ open sent acknowledged quoted in_production completed canceled expired ].freeze

    def index
      authorize PrintRequest

      @filter = STATUS_FILTERS.include?(params[:statut]) ? params[:statut] : "open"
      # One query for the counters, not one per tab.
      @counts = policy_scope(PrintRequest).group(:status).count
      @print_requests = filtered.includes(:client, design: :print_file_attachment).newest_first
    end

    def show
      authorize @print_request
      @sheet = PrintRequestSheet.call(print_request: @print_request)
    end

    def update
      authorize @print_request

      unless advance
        return redirect_to workshop_print_request_path(@print_request), alert: t(".impossible")
      end

      @print_request.save!
      PrintRequestMailer.status_changed(@print_request).deliver_later

      redirect_to workshop_print_request_path(@print_request), notice: t(".updated")
    end

    private
      # The event names a form field, so it is dispatched by hand rather than
      # sent. Four literal calls read better than a guarded `public_send`, and
      # they leave no doubt — for a reader or for Brakeman — that nothing a
      # client types ever names a method.
      #
      # `cancel` is deliberately absent: calling a job off is the client's.
      def advance
        case params[:event]
        when "acknowledge"      then @print_request.may_acknowledge? && @print_request.acknowledge!
        when "quote"            then @print_request.may_quote? && @print_request.quote!
        when "start_production" then @print_request.may_start_production? && @print_request.start_production!
        when "complete"         then @print_request.may_complete? && @print_request.complete!
        else false
        end
      end

      def set_print_request
        @print_request = policy_scope(PrintRequest).find_by!(token: params[:token])
      end

      def filtered
        scope = policy_scope(PrintRequest)
        @filter == "open" ? scope.where(status: %w[ sent acknowledged quoted in_production ]) : scope.where(status: @filter)
      end
  end
end
