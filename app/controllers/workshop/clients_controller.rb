module Workshop
  # The shop's clients, and the requests waiting on it. See docs/SPEC.md,
  # "Rattachement d'un client à un atelier".
  #
  # A request is answered here, signed in — never from the email, whose links
  # are opened by whatever scans the mail first. Accepting puts the client on
  # this shop's generations; refusing, or later taking a client off the list,
  # stops that.
  class ClientsController < BaseController
    # Every list here is this shop's own; the policy check is on the shop.
    skip_after_action :verify_policy_scoped

    before_action :set_printer

    def index
      authorize @printer, :update?

      @pending = ClientAffiliation.pending.where(printer_id: @printer.id)
                                  .includes(:client).order(:created_at).to_a
      # Only those whose period is still running: a client whose thirty days
      # are over has to scan again or ask again, and is no longer this shop's.
      @clients = User.client.active.attached_to(@printer.id)
                     .order(:last_name, :first_name).to_a
      # How each client came in — the poster, the email, a named link: the
      # shop's follow-up, and what tells it which of its supports work.
      @admissions = ClientAffiliation.latest_admissions(printer_id: @printer.id, client_ids: @clients.map(&:id))
      @channels = WorkshopLinkChannel.where(printer_id: @printer.id).to_a
    end

    def accept
      authorize @printer, :update?

      affiliation = pending_affiliation
      affiliation.accept!
      AffiliationMailer.accepted(affiliation).deliver_later
      redirect_to workshop_clients_path, notice: t(".done", name: affiliation.client.full_name)
    end

    def decline
      authorize @printer, :update?

      affiliation = pending_affiliation
      affiliation.decline!
      AffiliationMailer.declined(affiliation).deliver_later
      redirect_to workshop_clients_path, notice: t(".done", name: affiliation.client.full_name)
    end

    # The client keeps their account and their designs; they simply stop
    # creating on this shop's plan until another shop takes them.
    def remove
      authorize @printer, :update?

      client = User.client.attached_to(@printer.id).find(params[:id])
      client.detach_from_workshop!
      AffiliationMailer.removed(client, @printer).deliver_later
      redirect_to workshop_clients_path, notice: t(".done", name: client.full_name)
    end

    # Thirty more days from today (decided on 09/10/2026): the shop's call,
    # for a client it wants to keep — never the client's.
    def extend_period
      authorize @printer, :update?

      client = User.client.attached_to(@printer.id).find(params[:id])
      client.attach_to!(@printer.id)
      redirect_to workshop_clients_path,
                  notice: t(".done", name: client.full_name, date: l(client.workshop_until.to_date, format: :long))
    end

    private
      # No listing yet means no clients: the profile comes first.
      def set_printer
        @printer = current_printer
        redirect_to edit_workshop_profile_path, alert: t("workshop.links.show.no_listing") unless @printer&.persisted?
      end

      # Another shop's request is a 404, not a refusal: it is not this shop's
      # to see.
      def pending_affiliation
        ClientAffiliation.pending.includes(:client).where(printer_id: @printer.id).find(params[:id])
      end
  end
end
