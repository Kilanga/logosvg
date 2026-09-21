module Workshop
  # The link a shop hands to its customers: the URL, its QR code, and a poster
  # made to be printed and put on a counter.
  class LinksController < BaseController
    skip_after_action :verify_policy_scoped

    before_action :set_printer
    before_action :require_listing

    def show
      authorize @printer, :update?
      @statistics = link_statistics
    end

    # SVG for the poster and for print; PNG for whatever a shop pastes into its
    # own flyer. Both come from the same code.
    def qr
      authorize @printer, :update?

      case params[:format]
      when "png"
        send_data WorkshopQrCode.png(share_url), type: "image/png",
                  disposition: "attachment", filename: "#{@printer.slug}-qr.png"
      else
        send_data WorkshopQrCode.svg(share_url), type: "image/svg+xml",
                  disposition: "attachment", filename: "#{@printer.slug}-qr.svg"
      end
    end

    # Its own layout: this page is made to come out of a printer, not to be
    # read inside the workshop console.
    def poster
      authorize @printer, :update?

      @qr = WorkshopQrCode.svg(share_url, size: 320)
      render layout: "poster"
    end

    private
      def set_printer = @printer = current_printer

      # There is no link to share until the listing exists and is public.
      def require_listing
        return if @printer&.persisted?

        redirect_to edit_workshop_profile_path, alert: t("workshop.links.show.no_listing")
      end

      def share_url = workshop_link_url(slug: @printer.slug)

      # Atelier+ buys the statistics. Without it the page still shows the link,
      # the QR code and the poster — those are what a shop needs to be found.
      def link_statistics
        return nil unless @printer.subscription&.featured?

        {
          series: WorkshopLinkVisit.series(@printer, days: 30),
          designs: Design.where(printer: @printer).where(created_at: 30.days.ago..).count,
          print_requests: @printer.print_requests.where(created_at: 30.days.ago..).count
        }
      end
  end
end
