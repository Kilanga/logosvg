# How a client may enter a workshop on this visit (decided on 09/10/2026):
#
#   :member  — already the shop's client, nothing to do;
#   :sheet   — a numbered single-use sheet from the shop: admitted, sheet spent;
#   :poster  — the shop's poster, link or QR code: admitted, but only a client
#              who has never been this shop's — a former one asks again;
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
    elsif sheet then :sheet
    elsif @shop_context.invited_by?(@printer) && ClientAffiliation.first_time?(client: @client, printer: @printer)
      :poster
    else :request
    end
  end

  def admits? = kind.in?(%i[ sheet poster ])

  # In, or false if the sheet was spent by someone else in the meantime.
  def admit!(client = @client)
    admitted = ClientAffiliation.admit!(client: client, printer: @printer,
                                        source: kind == :sheet ? :sheet : :invitation,
                                        invite: (sheet if kind == :sheet))
    @shop_context.forget_invitations! if admitted
    admitted
  end

  private
    def sheet = defined?(@sheet) ? @sheet : (@sheet = @shop_context.sheet_for(@printer))
end
