# Preview at http://localhost:3000/rails/mailers/workshop_link_mailer
class WorkshopLinkMailerPreview < ActionMailer::Preview
  # The email as a client receives it, with the shop's word.
  def invite
    WorkshopLinkMailer.invite(Printer.take, "client@example.invalid",
                              "Comme convenu ce matin : pour les t-shirts de l'association, partez sur la sérigraphie deux couleurs.")
  end

  # Without a word from the shop.
  def invite_without_message
    WorkshopLinkMailer.invite(Printer.take, "client@example.invalid", nil)
  end
end
