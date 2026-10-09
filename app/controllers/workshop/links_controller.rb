module Workshop
  # The link a shop hands to its customers: the URL, its QR code, and a poster
  # made to be printed and put on a counter.
  class LinksController < BaseController
    skip_after_action :verify_policy_scoped

    before_action :set_printer
    before_action :require_listing

    def show
      authorize @printer, :update?
      # Queried on its own: `@printer` comes from `current_printer`, which
      # preloads only what every workshop screen reads, and `strict_loading`
      # refuses to walk to an association nobody asked for.
      @channels = WorkshopLinkChannel.where(printer: @printer).order(:created_at, :id).to_a
      @statistics = link_statistics
    end

    # SVG for the poster and for print; PNG for whatever a shop pastes into its
    # own flyer. Both come from the same code. With `canal`, the code of one of
    # the shop's named links; without, the one on the poster.
    def qr
      authorize @printer, :update?

      url = share_url(source: qr_source)

      case params[:format]
      when "png"
        send_data WorkshopQrCode.png(url), type: "image/png",
                  disposition: "attachment", filename: "#{@printer.slug}-#{qr_source}.png"
      else
        send_data WorkshopQrCode.svg(url), type: "image/svg+xml",
                  disposition: "attachment", filename: "#{@printer.slug}-#{qr_source}.svg"
      end
    end

    # Its own layout: this page is made to come out of a printer, not to be
    # read inside the workshop console.
    def poster
      authorize @printer, :update?

      @qr = WorkshopQrCode.svg(share_url(source: WorkshopLinkVisit::QR), size: 320)
      render layout: "poster"
    end

    # A new code for the poster, the QR code and every named link: the old
    # ones stop admitting anyone and lead to the shop's page, where a visitor
    # can only ask. Printed posters have to be printed again.
    def regenerate_code
      authorize @printer, :update?

      @printer.regenerate_invite_code!
      redirect_to workshop_link_share_path, notice: t(".done")
    end

    private
      def set_printer = @printer = current_printer

      # There is no link to share until the listing exists and is public.
      def require_listing
        return if @printer&.persisted?

        redirect_to edit_workshop_profile_path, alert: t("workshop.links.show.no_listing")
      end

      def share_url(source: nil) = workshop_invite_url(slug: @printer.slug, code: @printer.invite_code, s: source)

      # A channel that is not this shop's is a 404, not a fallback: a download
      # named after the wrong channel would be a QR code that counts elsewhere.
      def qr_source
        @qr_source ||= if params[:canal].present?
          @printer.link_channels.find_by!(key: params[:canal]).key
        else
          WorkshopLinkVisit::QR
        end
      end

      # Atelier+ buys the statistics. Without it the page still shows the link,
      # the QR code and the poster — those are what a shop needs to be found.
      def link_statistics
        return nil unless @printer.subscription&.featured?

        requests = @printer.print_requests.where(created_at: 30.days.ago..)

        {
          series: WorkshopLinkVisit.series(@printer, days: 30),
          sources: WorkshopLinkVisit.by_source(@printer, days: 30),
          designs: Design.where(printer: @printer).where(created_at: 30.days.ago..).count,
          print_requests: requests.count,
          # Of those, how many came from a design this shop's own funnel
          # produced, versus a client who found the shop some other way —
          # the directory, most often — for a design started elsewhere.
          print_requests_from_link: requests.from_designs_printer.count
        }
      end
  end
end
