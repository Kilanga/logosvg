# A shop emails its link to a client it already spoke to (decided on
# 10/10/2026). The link is the shop's own — the poster's code, counted as
# `email` — so the client is admitted like anyone who scans the poster, and the
# shop sees in its list that this one came by email.
#
# Not a prospecting tool: once per address and per shop, and so many a day.
# Both are checked and the row written inside a lock on the shop, so two clicks
# on « Envoyer » cannot both pass; the unique index stands behind the check.
class SendWorkshopLink
  Result = Data.define(:error) do
    def success? = error.nil?
  end

  def self.call(...) = new(...).call

  def initialize(printer:, email:)
    @printer = printer
    @email = email.to_s.strip.downcase
  end

  def call
    return failure(:not_listed) unless @printer.listed?
    return failure(:invalid_email) unless @email.match?(URI::MailTo::EMAIL_REGEXP)

    digest = WorkshopLinkEmail.digest(@email)
    error = @printer.with_lock do
      if WorkshopLinkEmail.exists?(printer_id: @printer.id, recipient_digest: digest) then :already_sent
      elsif WorkshopLinkEmail.sent_today(@printer) >= WorkshopLinkEmail.daily_limit then :limit_reached
      else
        WorkshopLinkEmail.create!(printer: @printer, recipient_digest: digest)
        nil
      end
    end
    return failure(error) if error

    WorkshopLinkMailer.invite(@printer, @email).deliver_later
    Result.new(error: nil)
  end

  private
    def failure(key) = Result.new(error: key)
end
