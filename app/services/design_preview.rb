# The only rendering of a design a client ever receives.
#
# It is a raster of the *print file* — not of the image the model drew. The two
# differ on purpose: white has become unprinted textile, near colours have been
# merged to fit the ink count. Showing the client the original would be asking
# them to approve something other than what gets printed.
#
# Watermarked, capped in width, and produced server-side: the print file itself
# never leaves for the client. See docs/SPEC.md, "Fichiers".
class DesignPreview
  WIDTH_PX = 1200
  CACHE_TTL = 1.day

  def self.call(design) = new(design).call

  def initialize(design)
    @design = design
  end

  def call
    # Said out loud: every way this returns nil ends with a caller quietly
    # showing no preview, and "there was no file" and "the file was refused"
    # are very different faults to chase.
    unless @design.print_file.attached?
      Rails.logger.info("[preview] no print file attached to #{@design.token}")
      return nil
    end

    # A refusal is not cached: it is a fault to fix, not an answer to keep.
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL, skip_nil: true) { render }
  end

  private
    def cache_key = "design_preview/#{@design.token}/#{@design.print_file.blob.checksum}/#{WIDTH_PX}"

    def svg? = @design.print_file.blob.content_type == "image/svg+xml"

    # Inspected again, here, on the bytes actually about to be rendered. The
    # file was already checked when it was stored, but librsvg is what this
    # method hands it to, and a guard that depends on another class having done
    # its job is a guard that stops working the day someone attaches a file by
    # another route.
    def safe?(file)
      return true unless svg?

      bytes = file.read
      file.rewind

      result = SvgInspector.call(bytes)
      return true if result.valid?

      # The byte count is here because `:empty` and `:not_svg` on a file that
      # stored perfectly well mean the read came back short, not that the
      # designer sent something bad.
      Rails.logger.error(
        "[preview] refused the stored SVG for #{@design.token}: " \
        "#{result.reason} (#{bytes.to_s.bytesize} octets lus)"
      )
      false
    end

    def render
      @design.print_file.blob.open do |file|
        next nil unless safe?(file)

        image = Vips::Image.thumbnail(file.path, WIDTH_PX)
        # An SVG renders with transparency, and so does a cut-out PNG: the paper
        # behind it is what the workshop will not print, so it is shown white.
        image = image.flatten(background: [ 255, 255, 255 ]) if image.has_alpha?

        band = watermark(image.width)
        stamped = image.composite2(band, :over, x: 0, y: image.height - band.height)

        # Flattened again on the way out: compositing a semi-transparent band
        # puts an alpha channel back on, and the preview has no use for one.
        stamped = stamped.flatten(background: [ 255, 255, 255 ]) if stamped.has_alpha?
        stamped.write_to_buffer(".png")
      end
    end

    # Burnt into the pixels rather than laid over them in CSS: a watermark a
    # browser draws is a watermark a screenshot removes.
    def watermark(width)
      @watermark ||= begin
        text = Vips::Image.text(credit, width: width - 40, dpi: 72)
        band = text.embed(20, 12, width, text.height + 24)
        band.new_from_image([ 0, 0, 0 ]).bandjoin(band * 0.55).copy(interpretation: :srgb)
      end
    end

    # Le nom de l'atelier, sans passer par l'association : ce service est appelé
    # depuis un travail de fond comme depuis une requête, et le design y arrive
    # parfois sans rien de préchargé.
    def credit
      shop = Printer.where(id: @design.printer_id).pick(:name) if @design.printer_id

      I18n.t("designs.watermark", name: shop || Rails.application.config.tshirt.platform_name)
    end
end
