module Public
  # `/a/:slug` — the shop's own page for its clients — and `/a/:slug/:code`, the
  # link on its poster, its QR code and its named links. Numbered single-use
  # sheets land here too, through `/f/:code` (WorkshopSheetsController).
  #
  # Decided on 09/10/2026: a client belongs to one workshop, and only with that
  # workshop's agreement. The code is that agreement given in advance: whoever
  # holds it is admitted at once. The slug alone is public — it is in the
  # directory's URLs — so without the code a visitor can only ask, and the shop
  # decides in its space. See docs/SPEC.md, "Rattachement d'un client à un
  # atelier".
  class WorkshopLinksController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    # Joining is something an account does.
    before_action :require_authentication, only: :join
    before_action :set_printer

    # What a link preview, a search engine or a monitoring script calls itself.
    # A shared link is fetched by the messaging app before anyone taps it, so
    # without this a shop would count its own WhatsApp message as a visit.
    # An empty User-Agent is a script: every browser sends one.
    CRAWLER = /bot|crawl|spider|slurp|preview|facebookexternalhit|whatsapp|curl|wget|python-requests|lighthouse|uptime/i

    def show
      # Counted here rather than on the creation screen: this is the poster
      # being scanned, whether or not anything is drawn afterwards. Once per
      # visitor, though: already knowing the shop — from this session or from
      # the cookie a returning visitor agreed to — means a reload or a second
      # scan, not a second person.
      if new_visitor? && !crawler?
        WorkshopLinkVisit.record!(@printer, source: @printer.link_source(params[:s]))
      end
      shop_context.remember(@printer)

      # The code is taken and dropped from the address at once: it must not sit
      # in a browser history, a screenshot or the Referer of the next page.
      if params[:code].present?
        shop_context.invite!(@printer) if @printer.invite_code_matches?(params[:code])
        return redirect_to workshop_link_path(slug: @printer.slug)
      end

      # A client with an account who scanned the poster or a sheet: in, and
      # straight to work — that is also how one moves to another shop.
      # One of the shop's clients scanning it again goes straight to work too —
      # without a single day more: only the shop extends.
      if Current.user&.client? && (entry.admits? || (entry.kind == :member && shop_context.invited_by?(@printer)))
        return admit_and_create
      end

      # "J'ai déjà un compte" comes back here, where the page knows what to offer.
      session[:return_to_after_authenticating] = workshop_link_url(slug: @printer.slug) unless authenticated?

      @invited = entry.admits?
      @former = Current.user&.client? && shop_context.invited_by?(@printer) && !@invited &&
                Current.user.active_workshop_id != @printer.id
      @pending = Current.user&.client? &&
                 ClientAffiliation.pending.exists?(client_id: Current.user.id, printer_id: @printer.id)
    end

    # A signed-in client asking to join — from the directory, or from a link
    # without its code. With the code in this visit, there is nothing to ask.
    def join
      return redirect_to(space_path_for(Current.user), alert: t(".clients_only")) unless Current.user.client?
      return redirect_to(new_design_path) if entry.kind == :member
      return admit_and_create if entry.admits?

      if (affiliation = ClientAffiliation.request!(client: Current.user, printer: @printer))
        AffiliationMailer.requested(affiliation).deliver_later
      end
      redirect_to client_dashboard_path, notice: t(".requested", name: @printer.name)
    end

    private
      def set_printer
        # A shop that has been suspended, or a mistyped poster: the directory is
        # a better answer than a 404 for someone standing at a counter.
        @printer = Printer.listed.includes(:techniques).with_attached_logo.find_by(slug: params[:slug])
        redirect_to printers_path, alert: t("public.workshop_links.show.unknown") if @printer.nil?
      end

      def entry
        @entry ||= WorkshopEntry.new(client: (Current.user if Current.user&.client?),
                                     printer: @printer, shop_context: shop_context)
      end

      def admit_and_create
        return redirect_to(new_design_path) if entry.kind == :member

        if entry.admit!
          redirect_to new_design_path, notice: t("public.workshop_links.show.admitted",
                                                 name: @printer.name, date: l(Current.user.workshop_until.to_date, format: :long))
        else
          # The sheet was spent a moment ago, by someone else.
          redirect_to workshop_link_path(slug: @printer.slug), alert: t("public.workshop_sheets.show.spent")
        end
      end

      def new_visitor? = shop_context.printer_id != @printer.id

      def crawler? = request.user_agent.blank? || request.user_agent.match?(CRAWLER)
  end
end
