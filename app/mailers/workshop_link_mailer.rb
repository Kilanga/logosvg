# The email a shop sends to give its link to a client it already spoke to
# (decided on 10/10/2026). Written in the shop's voice and in its colours, from
# the platform's address — the only one allowed to send — with the shop as
# the reply address: the client answering writes to the shop, not to us.
#
# The link is the poster's, counted as `email`. The QR code goes as an inline
# attachment: Gmail and others drop `data:` images.
class WorkshopLinkMailer < ApplicationMailer
  layout "workshop_link_mailer"

  def invite(printer, email)
    @printer = Printer.find(printer.id)
    @palette = @printer.brand_palette
    @site = Rails.application.config.tshirt.platform_site
    @url = workshop_invite_url(slug: @printer.slug, code: @printer.invite_code, s: WorkshopLinkVisit::EMAIL)
    @figures = figures

    attachments.inline["qr.png"] = WorkshopQrCode.png(@url, size: 360)

    mail to: email,
         from: email_address_with_name(platform_address, t("mailers.workshop_link.invite.from", name: @printer.name, site: @site)),
         reply_to: email_address_with_name(@printer.orders_email, @printer.name),
         subject: t("mailers.workshop_link.invite.subject", name: @printer.name)
  end

  private
    # The numbers the steps quote, from the same settings as everywhere else.
    def figures
      settings = Rails.application.config.tshirt
      { proposals: settings.generation.fetch(:proposals_per_request) }
    end

    # The address of the platform's own sender, without the name it carries.
    def platform_address = Mail::Address.new(self.class.default[:from]).address
end
