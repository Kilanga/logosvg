# The only renderings of a design a client ever receives.
#
# The default variant is a raster of the *print file* — not of the image the
# model drew. The two differ on purpose: white has become unprinted textile,
# near colours have been merged to fit the ink count. Approving the design
# means approving this file, which is why it is the one shown by default.
#
# The `:source_png` variant exists only so the client can *compare* — the
# "rendu final / image d'origine" selector in docs/SPEC.md, "Détails
# d'interface à respecter". It never replaces the print file as what gets
# approved or sent to a workshop.
#
# Both are watermarked, capped in width, and produced server-side: neither
# file itself ever leaves for the client. See docs/SPEC.md, "Fichiers".
class DesignPreview
  WIDTH_PX = 1200
  CACHE_TTL = 1.day
  # `:garment` is the print file again, but keeping its transparency: it sits on
  # the t-shirt silhouette, where unprinted areas must show the fabric colour.
  VARIANTS = %i[ print_file source_png garment ].freeze

  def self.call(design, variant: :print_file) = new(design, variant: variant).call

  def initialize(design, variant: :print_file)
    @design = design
    @variant = VARIANTS.include?(variant) ? variant : :print_file
  end

  def call
    # Said out loud: every way this returns nil ends with a caller quietly
    # showing no preview, and "there was no file" and "the file was refused"
    # are very different faults to chase.
    unless attachment.attached?
      Rails.logger.info("[preview] no #{@variant} attached to #{@design.token}")
      return nil
    end

    # A refusal is not cached: it is a fault to fix, not an answer to keep.
    Rails.cache.fetch(cache_key, expires_in: CACHE_TTL, skip_nil: true) { render }
  end

  private
    def attachment = @variant == :source_png ? @design.source_png : @design.print_file

    def transparent? = @variant == :garment

    def cache_key = "design_preview/#{@design.token}/#{@variant}/#{attachment.blob.checksum}/#{WIDTH_PX}"

    def svg? = attachment.blob.content_type == "image/svg+xml"

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
        "[preview] refused the stored #{@variant} for #{@design.token}: " \
        "#{result.reason} (#{bytes.to_s.bytesize} octets lus)"
      )
      false
    end

    def render
      attachment.blob.open do |file|
        next nil unless safe?(file)

        image = Vips::Image.thumbnail(file.path, WIDTH_PX)
        # An SVG renders with transparency, and so does a cut-out PNG: the paper
        # behind it is what the workshop will not print, so it is shown white —
        # except on the garment, where the fabric itself shows through.
        image = image.flatten(background: [ 255, 255, 255 ]) if image.has_alpha? && !transparent?

        band = watermark(image.width)
        stamped = image.composite2(band, :over, x: 0, y: image.height - band.height)

        # Flattened again on the way out: compositing a semi-transparent band
        # puts an alpha channel back on, and the preview has no use for one.
        stamped = stamped.flatten(background: [ 255, 255, 255 ]) if stamped.has_alpha? && !transparent?
        AiProvenance.mark(stamped.write_to_buffer(".png"), content_type: "image/png")
      end
    end

    # Burnt into the pixels rather than laid over them in CSS: a watermark a
    # browser draws is a watermark a screenshot removes. Two lines — the
    # workshop's credit, then the AI mention the client must be able to see.
    def watermark(width)
      @watermark ||= begin
        lines = "#{ERB::Util.html_escape(credit)}\n#{ERB::Util.html_escape(I18n.t("designs.watermark_ai"))}"
        text = Vips::Image.text(lines, width: width - 40, dpi: 72)
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
