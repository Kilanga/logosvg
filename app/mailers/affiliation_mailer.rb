# A client joining a workshop. The workshop is told there is someone to answer,
# never asked to answer from the email: the decision is taken in its space,
# signed in. A one-click link in a mail is clicked by whatever scans the mail
# first. See docs/SPEC.md, "Rattachement d'un client à un atelier".
class AffiliationMailer < ApplicationMailer
  # To the workshop's account: someone wants to create through it.
  def requested(affiliation)
    load_affiliation(affiliation)

    mail to: @printer.user.email_address,
         subject: t("mailers.affiliation.requested.subject", name: @client.full_name)
  end

  # To the client: they can create now.
  def accepted(affiliation)
    load_affiliation(affiliation)

    mail to: @client.email_address,
         subject: t("mailers.affiliation.accepted.subject", name: @printer.name)
  end

  # To the client: no, and where to look instead.
  def declined(affiliation)
    load_affiliation(affiliation)

    mail to: @client.email_address,
         subject: t("mailers.affiliation.declined.subject", name: @printer.name)
  end

  # To the client the workshop took off its list.
  def removed(client, printer)
    @client = client
    @printer = printer

    mail to: @client.email_address,
         subject: t("mailers.affiliation.removed.subject", name: @printer.name)
  end

  private
    # Reloaded with what the email reads: a mailer job gets a bare record.
    def load_affiliation(affiliation)
      @affiliation = ClientAffiliation.includes(:client, printer: :user).find(affiliation.id)
      @client = @affiliation.client
      @printer = @affiliation.printer
    end
end
