module Workshop
  # The shop sends its link by email to a client it already spoke to (decided
  # on 10/10/2026). Every shop with a listing, subscribed at any level: it is
  # how a client met at the counter gets the link without the poster at hand.
  # See SendWorkshopLink for the limits.
  class LinkEmailsController < BaseController
    skip_after_action :verify_policy_scoped

    before_action :set_printer

    def create
      authorize @printer, :update?

      email = params.dig(:link_email, :email).to_s.strip
      result = SendWorkshopLink.call(printer: @printer, email: email)

      if result.success?
        redirect_to workshop_link_share_path, notice: t(".sent", email: email)
      else
        redirect_to workshop_link_share_path,
                    alert: t(".#{result.error}", limit: WorkshopLinkEmail.daily_limit)
      end
    end

    private
      def set_printer
        @printer = current_printer
        redirect_to edit_workshop_profile_path, alert: t("workshop.links.show.no_listing") unless @printer&.persisted?
      end
  end
end
