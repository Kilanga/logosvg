# The QR code a shop prints on its counter poster.
#
# Generated rather than stored: it encodes nothing but the shop's own URL, and
# a stored image would be one more thing to keep in step with a renamed slug.
class WorkshopQrCode
  # `H` corrects up to 30% of the symbol. A poster on a counter gets coffee on
  # it, and a code that survives that is worth the extra modules.
  ERROR_CORRECTION = :h

  def self.svg(url, **options) = new(url).svg(**options)
  def self.png(url, **options) = new(url).png(**options)

  def initialize(url)
    @url = url
  end

  # Inline SVG, so the poster prints at whatever size the paper allows without
  # going soft — the whole reason a QR code is drawn rather than photographed.
  def svg(size: 240)
    code.as_svg(
      module_size: 6, standalone: true, use_path: true,
      color: "1D2433", viewbox: true, svg_attributes: { width: size, height: size }
    )
  end

  def png(size: 600)
    code.as_png(size: size, border_modules: 2, fill: "white", color: "1D2433").to_s
  end

  private
    def code = @code ||= RQRCode::QRCode.new(@url, level: ERROR_CORRECTION)
end
