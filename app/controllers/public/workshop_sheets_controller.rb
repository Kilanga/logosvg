module Public
  # `/f/:code` — the QR code of a numbered client sheet (decided on 09/10/2026).
  # One sheet, one client, once: the code is held for this visit and spent when
  # the client signs up or, already signed in, joins. Then the shop's page.
  class WorkshopSheetsController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    def show
      invite = WorkshopInvite.includes(:printer).find_by(code: params[:code].to_s.downcase)
      printer = invite&.printer
      return redirect_to(printers_path, alert: t("public.workshop_links.show.unknown")) unless printer&.listed?

      shop_context.remember(printer)
      if invite.usable?
        shop_context.hold_sheet!(invite)
        redirect_to workshop_link_path(slug: printer.slug)
      else
        # Used, or withdrawn by the shop: its page, where one can still ask.
        redirect_to workshop_link_path(slug: printer.slug), alert: t(".spent")
      end
    end
  end
end
