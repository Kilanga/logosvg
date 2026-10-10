# How a client may enter a workshop on this visit (decided on 09/10/2026, the
# numbered sheets withdrawn on 10/10/2026):
#
#   :member  — already the shop's client, nothing to do;
#   :poster  — the shop's code, by its poster, QR code, a named link or the
#              email it sent: admitted, but only a client who has never been
#              this shop's — a former one asks again, and the shop validates;
#   :request — everything else: the shop decides.
#
# Only the shop extends a client's thirty days (a confirmed print request, or
# « Prolonger ») — scanning again does not. See docs/SPEC.md, "Rattachement
# d'un client à un atelier".
class WorkshopEntry
  def initialize(client:, printer:, shop_context:)
    @client = client
    @printer = printer
    @shop_context = shop_context
  end

  def kind
    @kind ||= if @client&.active_workshop_id == @printer.id then :member
    elsif @shop_context.invited_by?(@printer) && ClientAffiliation.first_time?(client: @client, printer: @printer)
      :poster
    else :request
    end
  end

  def admits? = kind == :poster

  # The way in this visit came by — kept on the client's row, so the shop
  # knows which of its supports brought each client.
  def channel = @shop_context.channel_for(@printer)

  def admit!(client = @client)
    ClientAffiliation.admit!(client: client, printer: @printer, channel: channel)
    @shop_context.forget_invitations!
    true
  end
end
