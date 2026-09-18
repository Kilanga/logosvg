module Public
  # The directory and the shop pages. See docs/SPEC.md, "Écrans et routes".
  class PrintersController < BaseController
    def index
      @directory = PrinterDirectory.call(scope: policy_scope(Printer), filters: filters)
    end

    def show
      # Looked up across every listing, then authorized: a printer previewing
      # their own draft must reach it, a visitor must not.
      @printer = Printer.includes(:techniques).with_attached_logo.with_attached_photos
                        .find_by!(slug: params[:slug])
      authorize @printer
    end

    private
      def filters
        params.permit(:q, :department, :latitude, :longitude, :radius, :textile_label,
                      *PrinterDirectory::BOOLEAN_FILTERS, techniques: [])
              .to_h.symbolize_keys
      end
  end
end
