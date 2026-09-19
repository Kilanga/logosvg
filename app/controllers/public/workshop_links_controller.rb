module Public
  # `/a/:slug` — the link a shop prints on its counter poster.
  #
  # It remembers the shop for the session, so the client creates a design for
  # *that* workshop's machines without ever being asked to pick one. They can
  # still change it from the banner on the creation screen.
  class WorkshopLinksController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    def show
      printer = Printer.listed.find_by(slug: params[:slug])

      if printer
        session[:printer_id] = printer.id
        # Counted here rather than on the creation screen: this is the poster
        # being scanned, whether or not anything is drawn afterwards.
        WorkshopLinkVisit.record!(printer)
        redirect_to new_design_path
      else
        # A shop that has been suspended, or a mistyped poster: the directory is
        # a better answer than a 404 for someone standing at a counter.
        redirect_to printers_path, alert: t(".unknown")
      end
    end
  end
end
