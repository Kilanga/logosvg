module Workshop
  # Numbered single-use client sheets (decided on 09/10/2026): the shop prepares
  # a batch, prints it, hands one sheet per client, and sees here which sheet
  # went to whom. A sheet lost or given by mistake is withdrawn.
  class InvitesController < BaseController
    skip_after_action :verify_policy_scoped

    before_action :set_printer

    def index
      authorize @printer, :update?

      @invites = WorkshopInvite.where(printer_id: @printer.id).includes(:used_by)
                               .order(number: :desc).limit(300).to_a
    end

    def create
      authorize @printer, :update?

      batch = WorkshopInvite.issue!(@printer, params[:count])
      redirect_to workshop_invites_path, notice: t(".done", batch: batch)
    end

    # One A4 page per unspent sheet of the batch, ready to print or to save
    # as a PDF. Spent and withdrawn sheets are left out: reprinting a batch
    # gives only those still to hand out.
    def print
      authorize @printer, :update?

      @invites = WorkshopInvite.usable.where(printer_id: @printer.id, batch: params[:batch]).in_order.to_a
      return redirect_to(workshop_invites_path, alert: t(".nothing")) if @invites.empty?

      render layout: "poster"
    end

    def revoke
      authorize @printer, :update?

      invite = WorkshopInvite.usable.where(printer_id: @printer.id).find(params[:id])
      invite.revoke!
      redirect_to workshop_invites_path, notice: t(".done", number: invite.number)
    end

    private
      def set_printer
        @printer = current_printer
        redirect_to edit_workshop_profile_path, alert: t("workshop.links.show.no_listing") unless @printer&.persisted?
      end
  end
end
