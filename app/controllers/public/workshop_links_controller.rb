module Public
  # `/a/:slug` — the link a shop prints on its counter poster.
  #
  # It remembers the shop for the session, so the client creates a design for
  # *that* workshop's machines without ever being asked to pick one. They can
  # still change it from the banner on the creation screen.
  class WorkshopLinksController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    # What a link preview, a search engine or a monitoring script calls itself.
    # A shared link is fetched by the messaging app before anyone taps it, so
    # without this a shop would count its own WhatsApp message as a visit.
    # An empty User-Agent is a script: every browser sends one.
    CRAWLER = /bot|crawl|spider|slurp|preview|facebookexternalhit|whatsapp|curl|wget|python-requests|lighthouse|uptime/i

    def show
      printer = Printer.listed.find_by(slug: params[:slug])

      if printer
        # Counted here rather than on the creation screen: this is the poster
        # being scanned, whether or not anything is drawn afterwards. Once per
        # visitor, though: already knowing the shop — from this session or from
        # the cookie a returning visitor agreed to — means a reload or a second
        # scan, not a second person.
        if new_visitor?(printer) && !crawler?
          WorkshopLinkVisit.record!(printer, source: printer.link_source(params[:s]))
        end

        shop_context.remember(printer)
        redirect_to new_design_path
      else
        # A shop that has been suspended, or a mistyped poster: the directory is
        # a better answer than a 404 for someone standing at a counter.
        redirect_to printers_path, alert: t(".unknown")
      end
    end

    private
      def new_visitor?(printer) = shop_context.printer_id != printer.id

      def crawler? = request.user_agent.blank? || request.user_agent.match?(CRAWLER)
  end
end
