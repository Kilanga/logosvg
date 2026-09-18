module Admin
  # Listings waiting for a decision, and the decision itself.
  class PrintersController < BaseController
    def index
      @printers = policy_scope(Printer, policy_scope_class: PrinterPolicy::AdminScope)
                    .includes(:user, :techniques)
                    .order(Arel.sql("CASE status WHEN 1 THEN 0 ELSE 1 END"), updated_at: :desc)
    end

    def update
      @printer = Printer.find_by!(slug: params[:slug])
      authorize @printer, :publish?

      if @printer.update(status: requested_status)
        redirect_to admin_printers_path, notice: t(".#{requested_status}", name: @printer.name)
      else
        redirect_to admin_printers_path, alert: t(".failed", name: @printer.name)
      end
    end

    private
      # Only the two decisions an administrator makes. Anything else is refused
      # rather than coerced.
      def requested_status
        %w[ published suspended ].find { |s| s == params[:status] } ||
          raise(ActionController::BadRequest)
      end
  end
end
