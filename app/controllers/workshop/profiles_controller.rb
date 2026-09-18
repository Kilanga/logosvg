module Workshop
  # The shop's own listing: one per printer account, edited in sections and
  # submitted to the administration for publication.
  class ProfilesController < BaseController
    before_action :set_printer

    def edit
      authorize @printer, :edit?
      build_missing_techniques
    end

    def update
      authorize @printer, :update?

      if @printer.update(printer_params)
        redirect_to edit_workshop_profile_path, notice: t(".saved")
      else
        build_missing_techniques
        render :edit, status: :unprocessable_entity
      end
    end

    # Hands the listing to the administration. Publication is never the
    # printer's own decision — see docs/SPEC.md, "Validation manuelle".
    def submit
      authorize @printer, :submit?

      if @printer.update(status: :pending_review)
        redirect_to workshop_dashboard_path, notice: t(".submitted")
      else
        redirect_to edit_workshop_profile_path, alert: t(".incomplete")
      end
    end

    private
      # A printer who has never filled anything in still gets a form, not a
      # dead end.
      def set_printer
        @printer = Current.user.printer || Current.user.build_printer(orders_email: Current.user.email_address)
      end

      # One row per technique, always all of them: the form is a checklist of
      # what the shop can do, not a list to grow by hand.
      def build_missing_techniques
        (PrinterTechnique.techniques.keys - @printer.techniques.map(&:technique)).each do |technique|
          @printer.techniques.build(technique: technique)
        end
      end

      def printer_params
        params.expect(printer: [
          :name, :description, :address, :postal_code, :city,
          :orders_email, :phone, :website,
          :response_time_hours, :min_order_qty, :standard_lead_days,
          :express_available, :express_lead_hours,
          :ships, :shipping_lead, :shipping_price_note, :pickup,
          :provides_textile, :accepts_client_textile, :textile_label, :textile_brands_list,
          :max_print_width_cm, :max_print_height_cm, :price_note, :brand_color,
          :logo,
          { shipping_zones: [], placements: [], photos: [],
            techniques_attributes: [ [ :id, :technique, :max_colors, :_destroy, { accepted_formats: [] } ] ] }
        ])
      end
  end
end
