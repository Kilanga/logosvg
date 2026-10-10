# The shop's own colour (`printers.brand_color`), and what may be written on
# it and with it (decided on 10/10/2026, for the poster and the email a shop
# sends a client).
#
# A shop picks its colour for how it looks, not for its contrast, and a pale
# yellow is as likely as a navy. So the colour is never trusted as it is:
#
# - text laid on it is white when white reads at 4.5:1, ink otherwise; a
#   middle tone on which neither reads — a mid grey, a muted red — is taken
#   just dark enough for white;
# - the colour used as text on white is darkened towards ink until it reads
#   at 4.5:1.
#
# The QR code never takes the colour: ink on white, so every phone reads it.
class BrandPalette
  # The platform's own emulsion, for a shop that has not chosen.
  FALLBACK = "#1F5F7A".freeze
  INK = "#1D2433".freeze
  WHITE = "#FFFFFF".freeze
  MINIMUM_CONTRAST = 4.5

  def initialize(hex)
    @base = legible(rgb(hex.presence || FALLBACK))
  end

  def base = hex(@base)

  # White or ink, whichever reads on the colour.
  def on_base = contrast(@base, rgb(WHITE)) >= MINIMUM_CONTRAST ? WHITE : INK

  # The colour, dark enough to be read as text on white paper.
  def text
    @text ||= begin
      ink = rgb(INK)
      step = (0..20).find { |i| contrast(mix(@base, ink, i / 20.0), rgb(WHITE)) >= MINIMUM_CONTRAST }
      hex(mix(@base, ink, step.to_i / 20.0))
    end
  end

  # The colour cut with white: `0.7` keeps 30% of it. For the control strip at
  # the foot of the poster, never for anything that carries text.
  def tint(amount) = hex(mix(@base, rgb(WHITE), amount))

  private
    # The colour itself, or — when neither white nor ink reads on it — the
    # nearest darker shade on which white does.
    def legible(channels)
      white = rgb(WHITE)
      return channels if contrast(channels, white) >= MINIMUM_CONTRAST || contrast(channels, rgb(INK)) >= MINIMUM_CONTRAST

      step = (1..20).find { |i| contrast(mix(channels, rgb(INK), i / 20.0), white) >= MINIMUM_CONTRAST }
      mix(channels, rgb(INK), step / 20.0)
    end

    def rgb(value) = value.delete_prefix("#").scan(/../).map { |pair| pair.to_i(16) }

    def hex(channels) = "#" + channels.map { |c| c.round.clamp(0, 255).to_s(16).rjust(2, "0") }.join.upcase

    def mix(from, to, amount) = from.zip(to).map { |a, b| a + (b - a) * amount }

    # WCAG 2 relative luminance and contrast ratio.
    def luminance(channels)
      r, g, b = channels.map do |c|
        c /= 255.0
        c <= 0.03928 ? c / 12.92 : ((c + 0.055) / 1.055)**2.4
      end
      0.2126 * r + 0.7152 * g + 0.0722 * b
    end

    def contrast(a, b)
      light, dark = [ luminance(a), luminance(b) ].minmax.reverse
      (light + 0.05) / (dark + 0.05)
    end
end
