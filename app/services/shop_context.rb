# The workshop a visitor was sent by, and what they let us remember about it.
#
# Two layers, and only the second needs consent:
#
# 1. the session, which knows the shop until the browser closes. It is what makes
#    the site work — the creation screen shows that shop's techniques — so it is
#    strictly necessary and never asked about;
# 2. a signed cookie that keeps the shop for `attribution_cookie_days`, so a
#    client who scans the poster on a phone and designs the shirt on a computer
#    the next evening is still that shop's client. That one is set only after an
#    explicit "accept", and removed on "decline".
#
# The visitor's answer is itself a cookie (`cookie_consent`): recording a refusal
# is the one thing that cannot wait for consent.
class ShopContext
  CONSENT_KEY = :cookie_consent
  SHOP_KEY = :shop_ref
  INVITE_KEY = :invited_printer_id
  CHANNEL_KEY = :invited_channel
  CHOICES = %w[ accepted declined ].freeze

  def initialize(cookies:, session:, settings: Rails.application.config.tshirt.privacy)
    @cookies = cookies
    @session = session
    @settings = settings
  end

  # :accepted, :declined, or nil while nobody has answered. Anything else in the
  # cookie — an old value, a hand-edited one — is no answer.
  def choice
    value = @cookies[CONSENT_KEY].to_s
    value.to_sym if CHOICES.include?(value)
  end

  def accepted? = choice == :accepted
  def declined? = choice == :declined
  def undecided? = choice.nil?

  # The banner is for someone a shop just sent us. A visitor who came in by the
  # front door has been offered no cookie, so there is nothing to ask.
  def choice_pending? = undecided? && @session[:printer_id].present?

  # The session wins: it is what this visit was told. The cookie only speaks for
  # a visit that arrived with none — and only while consent stands.
  def printer_id
    @session[:printer_id] || (@cookies.signed[SHOP_KEY] if accepted?)
  end

  # A visit through a shop's link or QR code.
  def remember(printer)
    @session[:printer_id] = printer.id
    write_shop(printer.id) if accepted?
  end

  # The shop's own code was in the link — the poster, the QR code, a named
  # link, the email the shop sent. Session only, never the cookie: the code
  # admits a client without the shop deciding, so it must not outlive the
  # visit it came with. `channel` is which of those it was, for the shop's
  # list of clients.
  def invite!(printer, channel: nil)
    @session[INVITE_KEY] = printer.id
    @session[CHANNEL_KEY] = channel
  end

  def invited_by?(printer) = printer.present? && @session[INVITE_KEY] == printer.id

  # The way in this visit came by, while it still speaks for `printer`.
  def channel_for(printer) = (@session[CHANNEL_KEY] if invited_by?(printer))

  # Once used, the code should not go on speaking for this visit.
  def forget_invitations!
    @session.delete(INVITE_KEY)
    @session.delete(CHANNEL_KEY)
  end

  # The shop a sign-up would join, and whether it admits at once: the invited
  # shop. Failing that, the shop this visit or the cookie knows — which can
  # only be asked.
  def invited_printer_id = @session[INVITE_KEY]

  # Accepting keeps the shop the visitor is looking at right now, not just the
  # next one: they have already scanned the poster by the time they see the banner.
  def accept!
    write_choice("accepted")
    write_shop(@session[:printer_id]) if @session[:printer_id].present?
  end

  def decline!
    write_choice("declined")
    @cookies.delete(SHOP_KEY)
  end

  private
    def write_choice(value)
      @cookies[CONSENT_KEY] = {
        value: value, expires: @settings.fetch(:consent_cookie_months).months.from_now,
        httponly: true, same_site: :lax
      }
    end

    def write_shop(printer_id)
      @cookies.signed[SHOP_KEY] = {
        value: printer_id, expires: @settings.fetch(:attribution_cookie_days).days.from_now,
        httponly: true, same_site: :lax
      }
    end
end
