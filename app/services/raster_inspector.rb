# Checks a PNG before it is stored or handed to a workshop.
#
# The counterpart of SvgInspector for raster output. What matters here is not
# scripts but truth: that the file is really a PNG, that it has the transparency
# a DTF press needs, and that its pixels actually cover the size asked for. A
# 600 px image stretched to 25 cm prints as a blur, and nobody finds out until
# it is on a garment.
#
# See docs/SPEC.md, "Fichiers".
class RasterInspector
  MAX_BYTES = 25.megabytes
  PNG_SIGNATURE = "\x89PNG\r\n\x1A\n".b.freeze

  # Below this, a workshop will not print it. 150 dpi is the figure a DTF shop
  # commonly accepts; the platform warns rather than refuses above it.
  MINIMUM_DPI = 150

  Result = Data.define(:valid, :reason, :width_px, :height_px, :dpi, :has_alpha, :warnings) do
    def valid? = valid
    def warnings? = warnings.any?
  end

  def self.call(...) = new(...).call

  def initialize(bytes, print_width_cm: nil)
    @bytes = bytes.to_s
    @print_width_cm = print_width_cm
  end

  def call
    return refuse(:too_large) if @bytes.bytesize > MAX_BYTES
    return refuse(:empty) if @bytes.empty?
    # Checked by content, not by extension: a renamed file is the oldest trick
    # there is.
    return refuse(:not_a_png) unless @bytes.start_with?(PNG_SIGNATURE)

    image = load
    return refuse(:unreadable) if image.nil?

    describe(image)
  end

  private
    def load
      Vips::Image.new_from_buffer(@bytes, "")
    rescue Vips::Error
      nil
    end

    def describe(image)
      dpi = effective_dpi(image.width)

      Result.new(
        valid: true, reason: nil,
        width_px: image.width, height_px: image.height,
        dpi: dpi, has_alpha: image.has_alpha?,
        warnings: warnings_for(image, dpi)
      )
    end

    # Warnings, not refusals: a workshop may well accept a file the platform
    # would rather it did not, and that is the workshop's call.
    def warnings_for(image, dpi)
      [
        (:no_transparency unless image.has_alpha?),
        (:low_resolution if dpi && dpi < MINIMUM_DPI)
      ].compact
    end

    # What the file really resolves to at the size it will be printed — not the
    # dpi written in its metadata, which says nothing about the pixels.
    def effective_dpi(width_px)
      return nil if @print_width_cm.to_f <= 0

      (width_px / (@print_width_cm / 2.54)).round
    end

    def refuse(reason)
      Result.new(valid: false, reason: reason, width_px: nil, height_px: nil,
                 dpi: nil, has_alpha: nil, warnings: [])
    end
end
