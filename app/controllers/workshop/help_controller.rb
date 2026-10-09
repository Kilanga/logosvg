module Workshop
  # The workshop's help: how the site works for it, its questions, and a sheet
  # it hands to its clients (decided on 09/10/2026). Nothing here is a record
  # of anyone's: the space check in SpaceController is the authorization.
  class HelpController < BaseController
    skip_after_action :verify_authorized
    skip_after_action :verify_policy_scoped

    def show; end

    # Made to be printed, or sent as a PDF, like the poster: the shop's own
    # QR code, and the steps a client goes through. Needs a listing — there is
    # no link to put on it before.
    def client_sheet
      @printer = current_printer
      unless @printer&.persisted?
        return redirect_to edit_workshop_profile_path, alert: t("workshop.links.show.no_listing")
      end

      @url = workshop_invite_url(slug: @printer.slug, code: @printer.invite_code, s: WorkshopLinkVisit::QR)
      @qr = WorkshopQrCode.svg(@url, size: 200)
      render layout: "poster"
    end
  end
end
