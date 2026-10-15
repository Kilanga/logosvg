# Whether a file a designer hands back was made from the watermarked preview
# rather than from the original (G2, reported on 15/10/2026: a version blown
# up from the 1200 px preview went through as « 2953 × 2953 px, 300 dpi »,
# watermark and all).
#
# Since 15/10/2026 the designer downloads the original once the review is
# theirs, so a version carrying the platform's mark is either a mistake or a
# shortcut — and in both cases a file the workshop would print with the
# workshop's name across it.
#
# The test compares rather than looks: the version is set side by side with
# the design's own preview, once with the mark and once without. A version
# that sits clearly closer to the marked one carries the mark. How much
# closer is measured against how much the mark changes this particular design,
# so a light mark on a busy picture is judged as fairly as a dark one on a
# plain picture. A reworked version — recoloured, redrawn, recomposed — is far
# from both and is never flagged.
#
# A warning, not a refusal: shown to the designer as they deliver, and to the
# client and an administrator beside the version.
class WatermarkCheck
  WIDTH_PX = DesignPreview::WIDTH_PX

  # A pixel counts as part of the mark when the mark moves it by this much, on
  # average per channel out of 255.
  MARK_STRENGTH = 12

  # The mark must cover at least this share of the picture (out of 255, as the
  # mask is 0 or 255) for the comparison to mean anything.
  MINIMUM_COVER = 255 * 0.01

  # Share of the mark's own weight by which the version must lean towards
  # the marked preview.
  LEAN = 0.5

  def self.call(...) = new(...).call

  def initialize(design, bytes)
    @design = design
    @bytes = bytes.to_s
  end

  # true when the version carries the mark; false when it does not; nil when
  # there is nothing to compare with.
  def call
    return nil if @bytes.empty? || !@design.print_file.attached?

    marked_png = DesignPreview.call(@design)
    return nil if marked_png.nil?

    marked = rgb(Vips::Image.new_from_buffer(marked_png, ""))
    clean = @design.print_file.blob.open { |file| rgb(Vips::Image.thumbnail(file.path, WIDTH_PX)) }
    version = rgb(Vips::Image.thumbnail_buffer(@bytes, WIDTH_PX))

    clean = fit(clean, marked)
    version = fit(version, marked)

    # Only where the mark is drawn: elsewhere the two previews are the same
    # picture, and comparing there only measures how much the version was
    # reworked, which drowns the mark.
    where = (clean - marked).abs.bandmean > MARK_STRENGTH
    return false if where.avg < MINIMUM_COVER

    mark = distance(clean, marked, where)
    to_marked = distance(version, marked, where)
    to_clean = distance(version, clean, where)
    Rails.logger.debug { "[watermark_check] mark=#{mark.round(1)} to_marked=#{to_marked.round(1)} to_clean=#{to_clean.round(1)}" }
    to_marked < to_clean && (to_clean - to_marked) > LEAN * mark
  rescue Vips::Error => e
    Rails.logger.warn("[watermark_check] #{@design.token}: #{e.message.lines.first&.strip}")
    nil
  end

  private
    # Three channels on white, as the preview is drawn: transparency is the
    # unprinted textile, shown white everywhere a client looks.
    def rgb(image)
      image = image.colourspace(:srgb) unless image.interpretation == :srgb
      image = image.flatten(background: [ 255, 255, 255 ]) if image.has_alpha?
      image = image.bandjoin([ image, image ]) if image.bands == 1
      image.extract_band(0, n: 3).cast(:float).copy_memory
    end

    def fit(image, target)
      return image if image.width == target.width && image.height == target.height

      image.resize(target.width.to_f / image.width, vscale: target.height.to_f / image.height)
    end

    # Mean difference over the masked pixels only.
    def distance(a, b, where)
      weight = where / 255.0
      ((a - b).abs.bandmean * weight).avg / weight.avg
    end
end
