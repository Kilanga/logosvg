class ApplicationMailer < ActionMailer::Base
  # L'atelier lit ce nom avant de lire le message : c'est la plateforme qui lui
  # écrit, pas une adresse anonyme. Surchargeable par l'environnement pour les
  # essais.
  default from: ENV.fetch("MAIL_FROM", "Prêt-à-tirer <ne-pas-repondre@pretatirer.fr>")
  # Someone who answers an email of the site writes to a mailbox somebody
  # reads (decided on 10/10/2026), not to the sending address, which reaches
  # nobody. A mailer with a better answer — the client, for a print request —
  # sets its own.
  default reply_to: -> { Rails.application.config.tshirt.support_email }
  layout "mailer"
  helper MoneyHelper

  # Retried for a day when Brevo refuses, and counted. See MailDeliveryJob.
  self.delivery_job = MailDeliveryJob
end
