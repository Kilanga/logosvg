# Preview at http://localhost:3000/rails/mailers/workshop_link_mailer
class WorkshopLinkMailerPreview < ActionMailer::Preview
  # The email as a client receives it.
  def invite
    WorkshopLinkMailer.invite(Printer.take, "client@example.invalid")
  end
end
