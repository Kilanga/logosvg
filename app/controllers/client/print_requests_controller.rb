module Client
  # Sending a finished design to a workshop, and following what becomes of it.
  #
  # The quote happens off the platform: what this screen produces is a complete,
  # unambiguous brief — the file, the technique, the textile, the sizes — so the
  # workshop can price it without a single follow-up email.
  class PrintRequestsController < BaseController
    before_action :set_design, only: %i[ new create ]
    before_action :set_print_request, only: %i[ show cancel ]

    rate_limit to: 10, within: 1.minute, only: :create,
               with: -> { redirect_to design_path(params[:design_token]), alert: t("flash.rate_limited") }

    def new
      @print_request = build_request
      authorize @print_request
    end

    def create
      @print_request = build_request(print_request_params)
      authorize @print_request

      unless @print_request.valid?
        return render :new, status: :unprocessable_entity
      end

      result = SendPrintRequest.call(print_request: @print_request)

      if result.success?
        redirect_to print_request_path(@print_request), notice: t(".sent", printer: @printer.name)
      else
        # A shop that cannot do the job, or a design not ready: the reason comes
        # from the rule itself, not from a sentence written here.
        flash.now[:alert] = result.error
        render :new, status: :unprocessable_entity
      end
    end

    def show
      authorize @print_request
    end

    def cancel
      authorize @print_request

      @print_request.cancel!
      @print_request.save!

      redirect_to print_request_path(@print_request), notice: t(".canceled")
    end

    private
      def set_design
        @design = policy_scope(Design).find_by!(token: params[:design_token])
        @printer = chosen_printer
      end

      def set_print_request
        @print_request = policy_scope(PrintRequest).find_by!(token: params[:token])
      end

      # The shop comes from the directory link that led here, or from the one
      # the design was created for.
      def chosen_printer
        Printer.listed.includes(:techniques).find_by(slug: params[:atelier]) || @design.printer
      end

      # Prefilled from the account and from the design: a client who has already
      # said who they are should not say it twice, and the size they generated
      # at is the size they are ordering.
      def build_request(attributes = {})
        PrintRequest.new(
          {
            design: @design, client: Current.user, printer: @printer,
            print_width_cm: @design.print_width_cm,
            contact_name: Current.user.full_name,
            contact_email: Current.user.email_address,
            contact_phone: Current.user.phone,
            contact_city: Current.user.city,
            textile_source: default_textile_source
          }.merge(attributes.to_h.symbolize_keys)
        )
      end

      # A shop that does not supply garments cannot be asked to.
      def default_textile_source
        @printer&.provides_textile? ? "printer" : "client"
      end

      def print_request_params
        params.expect(print_request: [
          :textile_source, :textile_model, :textile_color, :desired_on, :message,
          :contact_name, :contact_email, :contact_phone, :contact_city,
          { placements: [], sizes: {} }
        ]).merge(consent_attributes)
      end

      # The consent is recorded as given, with the version of the text that was
      # on screen — not with today's.
      def consent_attributes
        return {} unless params.dig(:print_request, :consent) == "1"

        { consent_text_version: Rails.application.config.tshirt.privacy[:consent_text_version],
          consented_at: Time.current }
      end
  end
end
