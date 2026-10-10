# The email a shop sends a client to give its link (decided on 10/10/2026):
# written here, sent from the shop's own mail app.
#
# It used to go out from the platform, through Brevo. But the Brevo plan caps
# every email the site sends — print requests, password resets — at 300 a day,
# and a shop writing to its clients is better coming from its own address
# anyway. So the page opens the shop's mail app on this message (`mailto:`),
# or lets it copy the text; the shop types the address and sends it.
#
# Plain text, then: a mail app takes nothing else from a link. The link is the
# poster's, counted as `email`, so « Mes clients » still says where each client
# came from.
class WorkshopLinkMessage
  SCOPE = "workshop.links.message".freeze

  def initialize(printer, url:)
    @printer = printer
    @url = url
  end

  def subject = I18n.t("subject", scope: SCOPE, name: @printer.name)

  def body
    [
      I18n.t("greeting", scope: SCOPE),
      I18n.t("intro", scope: SCOPE),
      @printer.link_email_note,
      "#{I18n.t('cta', scope: SCOPE)}\n#{@url}",
      "#{I18n.t('how', scope: SCOPE)}\n#{steps}",
      notes,
      @printer.name
    ].compact_blank.join("\n\n")
  end

  # `mailto:` with no address: the shop fills in its client's. Spaces as %20,
  # never `+`, which mail apps would print as a plus sign.
  def mailto
    "mailto:?subject=#{ERB::Util.url_encode(subject)}&body=#{ERB::Util.url_encode(body)}"
  end

  private
    def steps
      proposals = Rails.application.config.tshirt.generation.fetch(:proposals_per_request)

      I18n.t("steps", scope: SCOPE).each_with_index.map do |step, index|
        "#{index + 1}. #{I18n.interpolate(step, proposals: proposals)}"
      end.join("\n")
    end

    def notes = I18n.t("notes", scope: SCOPE).join("\n")
end
