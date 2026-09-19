# The emails a print request generates. The workshop's one is the deliverable:
# it carries the print file itself, which never reaches the client.
class PrintRequestMailer < ApplicationMailer
  # Everything the workshop needs to quote, in one message: the recap, the print
  # file, the watermarked preview so the job can be recognised at a glance, the
  # technical sheet, and a link to confirm receipt.
  def to_printer(print_request)
    @print_request = print_request
    @design = print_request.design
    @sheet = PrintRequestSheet.call(print_request: print_request)
    @confirmation_url = print_request_confirmation_url(print_request.confirmation_token)

    attach_files

    mail to: print_request.printer.orders_email,
         reply_to: print_request.contact_email,
         subject: t("mailers.print_request.to_printer.subject",
                    reference: print_request.token.first(8).upcase)
  end

  # The client's copy carries the preview, never the print file.
  def to_client(print_request)
    @print_request = print_request
    @design = print_request.design
    @sheet = PrintRequestSheet.call(print_request: print_request)

    attach_preview

    mail to: print_request.client.email_address,
         subject: t("mailers.print_request.to_client.subject",
                    printer: print_request.printer.name)
  end

  # Nothing after 48 hours. The files travel again: a workshop that lost the
  # first email should not have to ask for them.
  def reminder(print_request)
    @print_request = print_request
    @design = print_request.design
    @confirmation_url = print_request_confirmation_url(print_request.confirmation_token)

    attach_files

    mail to: print_request.printer.orders_email,
         subject: t("mailers.print_request.reminder.subject",
                    reference: print_request.token.first(8).upcase)
  end

  def expired(print_request)
    @print_request = print_request

    mail to: print_request.client.email_address,
         subject: t("mailers.print_request.expired.subject",
                    printer: print_request.printer.name)
  end

  def status_changed(print_request)
    @print_request = print_request

    mail to: print_request.client.email_address,
         subject: t("mailers.print_request.status_changed.subject",
                    printer: print_request.printer.name)
  end

  private
    def attach_files
      file = @print_request.final_file
      attachments[file.filename.to_s] = file.download if file.attached?

      attach_preview
    end

    def attach_preview
      preview = @print_request.preview_png
      attachments[preview.filename.to_s] = preview.download if preview.attached?
    end
end
