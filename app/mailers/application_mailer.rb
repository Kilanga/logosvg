class ApplicationMailer < ActionMailer::Base
  # L'atelier lit ce nom avant de lire le message : c'est la plateforme qui lui
  # écrit, pas une adresse anonyme. Surchargeable par l'environnement pour les
  # essais.
  default from: ENV.fetch("MAIL_FROM", "Prêt-à-tirer <ne-pas-repondre@pretatirer.fr>")
  layout "mailer"
end
